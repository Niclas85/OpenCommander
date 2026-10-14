"""Loopback-only FTP/FTPS fixture for live protocol validation."""
import os
import sys
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler, TLS_FTPHandler
from pyftpdlib.servers import FTPServer

root,port,kind,passive=sys.argv[1:5]
authorizer=DummyAuthorizer()
authorizer.add_user('fixture',os.environ['OPENCOMMANDER_FIXTURE_PASSWORD'],root,perm='elradfmwMT')
handler=TLS_FTPHandler if kind=='ftps' else FTPHandler
handler.authorizer=authorizer
# Let Windows allocate a free data port. A reserved consecutive range inside
# its ephemeral client range can collide with control connections in this test.
handler.passive_ports=None
handler.masquerade_address='127.0.0.1'
if kind=='ftps':
    from OpenSSL import SSL
    from pyftpdlib.handlers.ftps.data import TLS_DTPHandler
    from pyftpdlib.handlers.ftp.data import DTPHandler
    class FixtureTLSData(TLS_DTPHandler):
        def handle_read_event(self):
            super().handle_read_event()
            # Drain decrypted records already buffered by OpenSSL. Windows
            # select cannot signal bytes which are no longer in the TCP socket.
            while not self._closed and self._ssl_established and self.socket.pending():
                super().handle_read_event()

        def close(self):
            if self._ssl_established and self.receive and self.transfer_finished:
                # Send close_notify once after a complete upload. The fixture's
                # async two-way TLS shutdown otherwise spins awaiting a peer
                # which is waiting for FTP's final 226 reply.
                try:self.socket.shutdown()
                except (SSL.WantReadError,SSL.WantWriteError,SSL.Error):pass
                DTPHandler.close(self)
            else:
                super().close()
    handler.dtp_handler=FixtureTLSData
    handler.certfile=sys.argv[5];handler.keyfile=sys.argv[6]
    handler.tls_control_required=True;handler.tls_data_required=True
    handler.ssl_context=SSL.Context(SSL.TLS_SERVER_METHOD)
    handler.ssl_context.set_min_proto_version(SSL.TLS1_2_VERSION)
    handler.ssl_context.use_certificate_file(handler.certfile)
    handler.ssl_context.use_privatekey_file(handler.keyfile)
server=FTPServer(('127.0.0.1',int(port)),handler)
server.serve_forever(timeout=.1)
