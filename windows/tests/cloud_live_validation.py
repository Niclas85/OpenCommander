"""Live cloud checks confined to synthetic files in a unique test folder."""
import argparse
import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
from types import SimpleNamespace

REPO = Path(__file__).resolve().parents[2]
CONTEXT = json.loads((REPO / 'windows/build/live-context.json').read_text())
INSTALLED = Path(CONTEXT['installed'])
sys.path.insert(0, str(INSTALLED / 'source/linux'))
from opencommander import platform_support, rclone_runtime, windows_mounts, windows_native
platform_support.helper_command = lambda name: [str(INSTALLED / 'helpers/OpenCommanderHelper.exe'), name]
rclone_runtime.binary = lambda: str(INSTALLED / 'tools/rclone.exe')
from opencommander.operations import FileEngine
from opencommander.online_ui import private_config, mount_path
from opencommander.provider_mounts import register
from opencommander.desktop import host_environment
from opencommander.cloud_config import config_login_error
from PySide6.QtCore import QSettings


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--writes', action='store_true'); parser.add_argument('--provider'); parser.add_argument('--state-dir', type=Path); args=parser.parse_args()
    state = args.state_dir or Path(os.environ['LOCALAPPDATA']) / 'OpenCommander'
    settings = QSettings(str(state / 'settings.ini'), QSettings.IniFormat)
    profiles = json.loads(settings.value('online_profiles', '[]'))
    config = private_config(state)
    results=[]
    for profile in profiles:
        if profile['kind'] not in ('drive', 'onedrive', 'dropbox', 'iclouddrive'):
            continue
        if args.provider and profile['kind'] != args.provider:
            continue
        started=time.monotonic(); result={'provider':profile['kind']}
        try:
            probe = subprocess.run([rclone_runtime.binary(), '--config', str(config), 'lsjson', profile['id']+':', '--max-depth', '1', '--no-mimetype', '--contimeout', '5s', '--timeout', '10s', '--retries', '1', '--low-level-retries', '1'],
                                   env=host_environment(), capture_output=True, text=True, timeout=25)
            if probe.returncode:
                result.update(status='failed', error=config_login_error(config, profile['id'], probe.stderr))
                # Only known backend causes are reported; never output raw OAuth logs.
                logs=probe.stderr.lower()
                result['cause_flags']={flag:flag in logs for flag in ('accessnotconfigured','invalid_grant','insufficientpermissions','403','401','has not been used','disabled','client_id','google drive api','shared','blocked','retired','quota','ratelimit','permission','denied')}
            else:
                result['root_listing_count']=len(json.loads(probe.stdout))
                main_window=SimpleNamespace(state_dir=state,server_secrets={})
                root=windows_mounts.mount_profile(main_window,profile,threading.Event())
                register(root)
                result['mounted']=windows_native.mount_identity(root)['filesystem']=='fuse.rclone'
                if args.writes:
                    test_name='OpenCommander-Pruefung-'+CONTEXT['id']+'-'+str(time.time_ns())
                    engine=FileEngine(Path(CONTEXT['state'])/'cloud-operations'/test_name)
                    directory=root/test_name
                    engine.mkdir(root,test_name)
                    source=Path(CONTEXT['root'])/(test_name+'.bin');data=bytes(range(256))*1024
                    source.write_bytes(data)
                    operation=engine.transfer([source],directory)
                    assert (directory/source.name).read_bytes()==data
                    assert any(row['name']==source.name for row in windows_native.invoke('scan',str(directory)))
                    restarted=FileEngine(engine.state_dir);restarted.undo(operation['id'])
                    assert not (directory/source.name).exists()
                    result.update(upload_bytes=len(data), byte_comparison=True, frozen_helper_listing=True, persistent_undo=True, test_directory=test_name)
                result['status']='pass'
        except Exception as error:
            result.update(status='failed',error=str(error))
        result['seconds']=round(time.monotonic()-started,2);results.append(result)
        print(json.dumps(result,ensure_ascii=False),flush=True)
    report=REPO/'windows/build/cloud-live-results.json'
    history=json.loads(report.read_text(encoding='utf-8')) if report.exists() else []
    report.write_text(json.dumps(history+results,ensure_ascii=False,indent=2),encoding='utf-8')


if __name__=='__main__': main()
