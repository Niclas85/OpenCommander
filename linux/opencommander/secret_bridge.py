#!/usr/bin/python3
"""Small host Secret Service / SSH askpass bridge. Never log credentials."""
import json
import os
import sys

if os.environ.get('OPENCOMMANDER_ASKPASS') == '1':
    sys.stdout.write(os.environ.get('OPENCOMMANDER_KEY_PASSPHRASE', '') + '\n')
    sys.exit(0)

try:
    import gi
    gi.require_version('Secret', '1')
    from gi.repository import Secret
    request = json.load(sys.stdin)
    schema = Secret.Schema.new('org.opencommander.Server', Secret.SchemaFlags.NONE,
                               {'profile': Secret.SchemaAttributeType.STRING,
                                'state': Secret.SchemaAttributeType.STRING})
    attributes = {'profile': request['profile'], 'state': request['state']}
    action = request['action']
    if action == 'store':
        if not Secret.password_store_sync(schema, attributes, Secret.COLLECTION_DEFAULT,
                                          'OpenCommander server login', request['secret'], None):
            raise RuntimeError()
        result = True
    elif action == 'clear':
        result = Secret.password_clear_sync(schema, attributes, None)
    elif action == 'lookup':
        result = Secret.password_lookup_sync(schema, attributes, None)
    else:
        raise ValueError()
    print(json.dumps({'result': result}))
except Exception:
    print(json.dumps({'error': 'Linux-Schlüsselbund nicht verfügbar oder gesperrt / Keyring unavailable or locked'}))
    sys.exit(1)
