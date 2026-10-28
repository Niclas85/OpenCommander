"""Real loopback protocol servers, actual WinFsp mounts, synthetic data only."""
import datetime
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import threading
import time
import traceback
from types import SimpleNamespace

REPO = Path(__file__).resolve().parents[2]
CONTEXT = json.loads((REPO/'windows/build/live-context.json').read_text())
INSTALLED=Path(CONTEXT['installed'])
sys.path.insert(0,str(INSTALLED/'source/linux'))
from opencommander import platform_support,rclone_runtime,windows_native,windows_mounts,server_connections
from opencommander.online_ui import private_config
from opencommander.desktop import host_environment
from opencommander.operations import FileEngine
platform_support.helper_command=lambda name:[str(INSTALLED/'helpers/OpenCommanderHelper.exe'),name]
rclone_runtime.binary=lambda:str(INSTALLED/'tools/rclone.exe')
# Keep the Windows FTP fixture's physical backing paths below MAX_PATH; Store
# app redirection of LOCALAPPDATA can add another long directory prefix.
BASE=REPO/'windows/build/protocol-fixtures'/str(time.time_ns())
BASE.mkdir(parents=True)


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0));return sock.getsockname()[1]


def certificates(folder):
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes,serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    name=x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME,'OpenCommander local test CA')])
    now=datetime.datetime.now(datetime.timezone.utc)
    cert=(x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
          .serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(minutes=2))
          .not_valid_after(now+datetime.timedelta(days=1)).add_extension(x509.BasicConstraints(ca=True,path_length=None),critical=True)
          .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address('127.0.0.1')),x509.DNSName('localhost')]),critical=False)
          .sign(key,hashes.SHA256()))
    certfile=folder/'test-ca.pem';keyfile=folder/'test-key.pem'
    certfile.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    keyfile.write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    return certfile,keyfile


def check(kind):
    folder=BASE/kind;folder.mkdir();backing=folder/'server-data';backing.mkdir()
    (backing/'read.txt').write_bytes(b'OpenCommander protocol read fixture')
    state=folder/'profile';config=private_config(state);port=free_port();password=secrets.token_urlsafe(24)
    main=SimpleNamespace(state_dir=state,server_secrets={'oc_fixture':password})
    profile=dict(id='oc_fixture',kind=kind,name='Local '+kind,server_login=True,auth_mode='password',secret_required=True)
    env=host_environment()
    serverkind='ftp' if kind=='ftps' else kind
    command=[rclone_runtime.binary(),'--config',str(config),'serve',serverkind,str(backing),'--addr',f'127.0.0.1:{port}','--user','fixture','--pass',password]
    if kind=='webdav':
        profile['server_login']=False
        obscured=subprocess.run([rclone_runtime.binary(),'obscure','-'],input=password+'\n',capture_output=True,text=True,check=True).stdout.strip()
        section=dict(type='webdav',url=f'http://127.0.0.1:{port}/',user='fixture',pass_=obscured)
        section['pass']=section.pop('pass_')
    else:
        section,details=server_connections.settings(kind,'127.0.0.1',port,'fixture','password')
        profile.update(details)
    if kind=='sftp':
        from cryptography.hazmat.primitives.asymmetric import ed25519
        from cryptography.hazmat.primitives import serialization
        key=ed25519.Ed25519PrivateKey.generate();keyfile=folder/'host-key'
        keyfile.write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.OpenSSH,serialization.NoEncryption()))
        public=key.public_key().public_bytes(serialization.Encoding.OpenSSH,serialization.PublicFormat.OpenSSH)
        known=folder/'known_hosts';known.write_bytes(f'[127.0.0.1]:{port} '.encode()+public+b'\n')
        section['known_hosts_file']=str(known);command+=['--key',str(keyfile)]
    if kind=='ftps':
        cert,key=certificates(folder);command+=['--cert',str(cert),'--key',str(key)]
        env['RCLONE_CA_CERT']=str(cert)
    if kind in ('ftp','ftps'):
        passive=free_port()
        command=[sys.executable,str(REPO/'windows/tests/ftp_fixture.py'),str(backing),str(port),kind,str(passive)]
        if kind=='ftps':command+=[str(cert),str(key)]
        env['OPENCOMMANDER_FIXTURE_PASSWORD']=password
        if kind=='ftps' and '--apache' in sys.argv:
            from cryptography import x509
            from cryptography.hazmat.primitives import serialization
            from cryptography.hazmat.primitives.serialization import pkcs12
            private=serialization.load_pem_private_key(key.read_bytes(),password=None)
            certificate=x509.load_pem_x509_certificate(cert.read_bytes())
            keystore=folder/'server.p12'
            keystore.write_bytes(pkcs12.serialize_key_and_certificates(b'fixture',private,certificate,None,serialization.BestAvailableEncryption(password.encode())))
            java=Path('C:/Program Files/JetBrains/IntelliJ IDEA 2026.2.3/jbr/bin/java.exe')
            classpath=str(REPO/'windows/build/apache-ftps')+';'+str(REPO/'windows/build/apache-ftps/*')
            command=[str(java),'-cp',classpath,'ApacheFtpsFixture',str(backing),str(port),str(keystore),str(folder/'users.properties')]
    server_connections.write_config(config,'oc_fixture',section)
    log=(folder/'server.log').open('w',encoding='utf-8')
    server=subprocess.Popen(command,env=env,stdout=log,stderr=log,stdin=subprocess.DEVNULL)
    mounted=None
    try:
        deadline=time.monotonic()+10
        while True:
            if server.poll() is not None:raise RuntimeError('Loopback server did not start; see private test log')
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.2):break
            except OSError:
                if time.monotonic()>deadline:raise RuntimeError('Loopback server startup timed out')
                time.sleep(.1)
        original=server_connections.credential_environment
        server_connections.credential_environment=lambda main,profile:dict(original(main,profile),**({'RCLONE_CA_CERT':str(cert)} if kind=='ftps' else {}))
        mount_log=(folder/'mount.log').open('w',encoding='utf-8')
        original_popen=subprocess.Popen
        def recorded_popen(command,**kwargs):
            if 'mount' in command:
                command=list(command)+['-vv'];kwargs['stderr']=mount_log
            return original_popen(command,**kwargs)
        subprocess.Popen=recorded_popen
        try:mounted=windows_mounts.mount_profile(main,profile,threading.Event())
        finally:
            server_connections.credential_environment=original
            subprocess.Popen=original_popen
        assert (mounted/'read.txt').read_bytes()==(backing/'read.txt').read_bytes()
        assert any(row['name']=='read.txt' for row in windows_native.invoke('scan',str(mounted)))
        source=folder/'Grüße 日本語.bin';data=bytes(range(256))*1024;source.write_bytes(data)
        engine=FileEngine(folder/'operations');operation=engine.transfer([source],mounted)
        assert (backing/source.name).read_bytes()==data
        restored=FileEngine(engine.state_dir);restored.undo(operation['id'])
        assert not (backing/source.name).exists()
        windows_mounts.unmount(mounted);mounted=None
        # Refuse changed SSH identity and an untrusted TLS chain with real servers.
        rejection=False
        if kind in ('sftp','ftps'):
            reject_env=server_connections.credential_environment(main,profile)
            if kind=='sftp':
                other=ed25519.Ed25519PrivateKey.generate().public_key().public_bytes(serialization.Encoding.OpenSSH,serialization.PublicFormat.OpenSSH)
                known.write_bytes(f'[127.0.0.1]:{port} '.encode()+other+b'\n')
            probe=subprocess.run([rclone_runtime.binary(),'--config',str(config),'lsjson','oc_fixture:','--contimeout','2s','--timeout','3s','--retries','1','--low-level-retries','1'],env=reject_env,capture_output=True,text=True,timeout=10)
            rejection=probe.returncode!=0
            assert rejection
        # Stop only our server and prove connection loss is bounded, not a hang.
        server.terminate();server.wait(timeout=5)
        client_env=server_connections.credential_environment(main,profile)
        if kind=='ftps':client_env['RCLONE_CA_CERT']=str(cert)
        started=time.monotonic()
        probe=subprocess.run([rclone_runtime.binary(),'--config',str(config),'lsjson','oc_fixture:','--contimeout','2s','--timeout','3s','--retries','1','--low-level-retries','1'],env=client_env,capture_output=True,text=True,timeout=10)
        assert probe.returncode!=0
        return dict(status='pass',upload_bytes=len(data),frozen_helper_listing=True,persistent_undo=True,untrusted_identity_rejected=rejection if kind in ('sftp','ftps') else None,
                    disconnect_seconds=round(time.monotonic()-started,2),graceful_unmount=True)
    finally:
        if mounted:
            windows_mounts.unmount(mounted)
        if server.poll() is None:
            server.terminate();server.wait(timeout=5)
        log.close()
        if 'mount_log' in locals():mount_log.close()


def main():
    results=[]
    for kind in ('ftp','ftps','sftp','webdav'):
        if len(sys.argv)>1 and kind!=sys.argv[1]:continue
        started=time.monotonic()
        try:result=check(kind)
        except Exception as error:result=dict(status='failed',error=str(error),traceback=traceback.format_exc())
        result.update(protocol=kind,seconds=round(time.monotonic()-started,2));results.append(result)
        if '--apache' in sys.argv:result['server']='Apache FtpServer 1.2.1'
        print(json.dumps(result,ensure_ascii=False),flush=True)
        report=REPO/'windows/build/protocol-live-results.json'
        history=json.loads(report.read_text(encoding='utf-8')) if report.exists() else []
        report.write_text(json.dumps(history+[result],ensure_ascii=False,indent=2),encoding='utf-8')


if __name__=='__main__':main()
