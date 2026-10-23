#import <Foundation/Foundation.h>
#import <unistd.h>
#import <stdlib.h>

// Foundation Process decomposes argv Unicode. Carry exact UTF-8 as ASCII,
// then exec without a shell, preserving PID, pipes and cancellation. No logs.
int main(void) {
    @autoreleasepool {
        const char *wire = getenv("OPENCOMMANDER_CLOUD_ARGV");
        if (!wire || strlen(wire) > 512 * 1024) return 125;
        NSData *data = [[NSData alloc] initWithBase64EncodedString:@(wire) options:0];
        unsetenv("OPENCOMMANDER_CLOUD_ARGV");
        id payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![payload isKindOfClass:[NSArray class]] || [payload count] != 2) return 125;
        NSString *binary = payload[0];
        NSArray *arguments = payload[1];
        if (![binary isKindOfClass:[NSString class]] || ![binary hasPrefix:@"/"] ||
            ![arguments isKindOfClass:[NSArray class]] || arguments.count > 4096) return 125;
        NSMutableArray *values = [NSMutableArray arrayWithObject:binary];
        [values addObjectsFromArray:arguments];
        char **argv = calloc(values.count + 1, sizeof(char *));
        if (!argv) return 125;
        for (NSUInteger i = 0; i < values.count; i++) {
            if (![values[i] isKindOfClass:[NSString class]]) return 125;
            NSData *utf8 = [values[i] dataUsingEncoding:NSUTF8StringEncoding];
            if (!utf8 || utf8.length > 64 * 1024 || memchr(utf8.bytes, 0, utf8.length)) return 125;
            argv[i] = strdup([values[i] UTF8String]);
            if (!argv[i]) return 125;
        }
        execv(argv[0], argv);
        return 126;
    }
}
