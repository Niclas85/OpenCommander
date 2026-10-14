import java.io.File;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import org.apache.ftpserver.FtpServer;
import org.apache.ftpserver.FtpServerFactory;
import org.apache.ftpserver.DataConnectionConfigurationFactory;
import org.apache.ftpserver.listener.ListenerFactory;
import org.apache.ftpserver.ssl.SslConfigurationFactory;
import org.apache.ftpserver.usermanager.PropertiesUserManagerFactory;
import org.apache.ftpserver.usermanager.impl.BaseUser;
import org.apache.ftpserver.usermanager.impl.WritePermission;

/** Independent, loopback-only Apache FtpServer fixture; no system service. */
public class ApacheFtpsFixture {
    public static void main(String[] args) throws Exception {
        FtpServerFactory factory = new FtpServerFactory();
        ListenerFactory listener = new ListenerFactory();
        listener.setServerAddress("127.0.0.1");
        listener.setPort(Integer.parseInt(args[1]));
        listener.setImplicitSsl(false);
        SslConfigurationFactory tls = new SslConfigurationFactory();
        tls.setKeystoreFile(new File(args[2]));
        tls.setKeystoreType("PKCS12");
        tls.setKeystorePassword(System.getenv("OPENCOMMANDER_FIXTURE_PASSWORD"));
        listener.setSslConfiguration(tls.createSslConfiguration());
        DataConnectionConfigurationFactory data = new DataConnectionConfigurationFactory();
        data.setPassiveAddress("127.0.0.1");
        data.setPassiveExternalAddress("127.0.0.1");
        listener.setDataConnectionConfiguration(data.createDataConnectionConfiguration());
        factory.addListener("default", listener.createListener());
        PropertiesUserManagerFactory users = new PropertiesUserManagerFactory();
        File usersFile = new File(args[3]);
        usersFile.createNewFile();
        users.setFile(usersFile);
        var manager = users.createUserManager();
        BaseUser user = new BaseUser();
        user.setName("fixture");
        user.setPassword(System.getenv("OPENCOMMANDER_FIXTURE_PASSWORD"));
        user.setHomeDirectory(args[0]);
        user.setEnabled(true);
        user.setAuthorities(List.of(new WritePermission()));
        manager.save(user);
        factory.setUserManager(manager);
        FtpServer server = factory.createServer();
        Runtime.getRuntime().addShutdownHook(new Thread(server::stop));
        server.start();
        new CountDownLatch(1).await();
    }
}
