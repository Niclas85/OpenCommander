import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile


def test_publisher_audit_rejects_native_secret_and_escaping_link(tmp_path):
    archive=tmp_path/'fixture.tar.gz'
    with tarfile.open(archive,'w:gz') as output:
        for name in ('opencommander','LICENSE','README.md','THIRD-PARTY.md','install-local.sh'):
            info=tarfile.TarInfo('opencommander/'+name);info.mode=0o755
            output.addfile(info,io.BytesIO())
        data=json.dumps({'client_id':'fixtureappkey123','flow':'pkce','client_secret':'forbidden-field'}).encode()
        info=tarfile.TarInfo('opencommander/_internal/opencommander/assets/dropbox-oauth.json');info.size=len(data)
        output.addfile(info,io.BytesIO(data))
        info=tarfile.TarInfo('opencommander/_internal/bad-link');info.type=tarfile.SYMTYPE
        info.linkname='../../../opencommander/opencommander';output.addfile(info)
    script=Path(__file__).resolve().parents[2]/'release/linux/check-package.py'
    result=subprocess.run([sys.executable,str(script),str(archive),'--require-publisher','dropbox'],capture_output=True,text=True)
    value=json.loads(result.stdout)
    assert result.returncode==1
    assert 'Escaping package link' in value['errors'] and 'Invalid publisher client' in value['errors']
    assert not value['publisher_clients']['dropbox']
    assert 'forbidden-field' not in result.stdout and 'forbidden-field' not in result.stderr
