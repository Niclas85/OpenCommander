"""Exercise the real OAuth hand-off without signing into a user's account."""
import json
import os
from pathlib import Path
import sys
import threading
import urllib.request
import urllib.error
import subprocess
import re
import argparse
from urllib.parse import urlsplit, parse_qs

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'linux'))
from opencommander import online_ui, rclone_runtime


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--provider',choices=('drive','onedrive','dropbox'),default='drive');args=parser.parse_args()
    context = json.loads((REPO / 'windows/build/live-context.json').read_text())
    rclone_runtime.binary = lambda: str(Path(context['installed']) / 'tools/rclone.exe')
    config = online_ui.private_config(Path(context['state']) / ('browser-probe-'+args.provider))
    cancel = threading.Event()
    result = {'provider':args.provider,'states': [], 'browser_callback': False, 'loopback_redirect': False}
    value = online_ui.command_json(config, ['config', 'create', 'oc_browser_probe', args.provider, '--non-interactive'], cancel)
    def browser(url):
        result['browser_callback'] = True
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        try:
            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect)
            opener.open(url, timeout=5)
        except urllib.error.HTTPError as error:
            location = error.headers.get('Location', '')
            expected={'drive':'accounts.google.com','onedrive':'login.microsoftonline.com','dropbox':'www.dropbox.com'}[args.provider]
            result['loopback_redirect'] = error.code in (301, 302, 303, 307) and urlsplit(location).hostname==expected
            redirect=parse_qs(urlsplit(location).query).get('redirect_uri',[''])[0]
            result['callback_host']=urlsplit(redirect).hostname;result['callback_port']=urlsplit(redirect).port
            # The provider's localhost callback must be reachable while waiting,
            # regardless of Windows choosing IPv4/IPv6 for the host name.
            try:
                opener.open(url.replace('127.0.0.1','localhost'),timeout=5)
            except urllib.error.HTTPError as local_error:
                result['localhost_reachable']=local_error.code in (301,302,303,307)
        finally:
            cancel.set()
    for _ in range(12):
        if not value.get('State'):
            break
        option = value.get('Option', {})
        result['states'].append({'state': value['State'], 'option': option.get('Name')})
        answer = 'true' if option.get('Name') == 'config_shared_client_id' else online_ui.automatic_auth_answer(args.provider, option)
        if answer is None:
            result['unexpected_question'] = option.get('Name')
            break
        try:
            value = online_ui.command_json(config, ['config', 'update', 'oc_browser_probe', '--continue', '--non-interactive', '--state', value['State']], cancel,
                                          result=answer, timeout=15, browser_callback=browser)
        except RuntimeError as error:
            result['cancelled_after_browser'] = cancel.is_set()
            if not cancel.is_set():
                result['error'] = str(error)
                env = online_ui.host_environment()
                env['RCLONE_STATE'] = value['State']
                env['RCLONE_RESULT'] = answer
                env['RCLONE_CONFIG_OC_BROWSER_PROBE_CONFIG_AUTH_NO_BROWSER'] = 'true'
                process = subprocess.Popen([rclone_runtime.binary(), '--config', str(config), 'config', 'update', 'oc_browser_probe', '--continue', '--non-interactive'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    stdout, stderr = process.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    stdout, stderr = process.communicate()
                # Report URL shape only; never emit an OAuth state or provider URL.
                logs = stderr.decode('utf-8', 'replace')
                result['url_shapes'] = [{'host': m.group(1), 'state_length': len(m.group(2))} for m in re.finditer(r'https?://([^/\s]+)/auth\?state=([^\s]+)', logs)]
                result['stderr_categories'] = {'waiting': 'Waiting for code' in logs, 'browser': 'browser' in logs.lower(), 'please_go': 'Please go to' in logs}
            break
    (REPO / ('windows/build/browser-probe-'+args.provider+'.json')).write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    if not result['browser_callback'] or not result['loopback_redirect'] or not result.get('localhost_reachable'):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
