import os
from pathlib import Path
import sys
import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'linux'))
sys.path.insert(0, str(REPO / 'linux/tests'))
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ['LANG'] = 'de_CH.UTF-8'  # Shared dialogue assertions use German labels.
import opencommander
os.environ['PATH'] = str(REPO / 'windows/build/runtime') + os.pathsep + os.environ.get('PATH', '')


@pytest.fixture(autouse=True)
def isolated_windows_tests(monkeypatch, tmp_path):
    # Shared Linux UI tests must never change real Windows shell associations.
    from opencommander import windows_shell
    monkeypatch.setattr(windows_shell, 'ask_default', lambda window: None)
    symlink = os.symlink
    def create_link(*args, **kwargs):
        try:
            return symlink(*args, **kwargs)
        except OSError as error:
            if getattr(error, 'winerror', None) == 1314:
                pytest.skip('Windows Developer Mode or symlink privilege required')
            raise
    monkeypatch.setattr(os, 'symlink', create_link)


# These assertions exercise Linux host services or POSIX-only fixture behavior.
# Windows equivalents live in test_windows.py; the original tests still run on Linux.
LINUX_ONLY = {
    'test_online_image_cancel_interrupts_blocked_read': 'POSIX FIFO fixture; native helper cancellation tested separately',
    'test_online_media_cache_preserves_bytes_permissions_and_actual_limit': 'POSIX mode assertion; binary download tested on Windows',
    'test_rclone_resume_restarts_only_verified_partial_file': 'Intercepts POSIX os.open; Windows uses CreateFile handles',
    'test_provider_unsupported_fsync_and_mode_keep_bytes_timestamps_and_undo': '/proc/self/fd fixture',
    'test_real_sync_errors_and_local_unsupported_sync_fail_safely': '/proc/self/fd fixture',
    'test_checkpoint_store_private_and_corruption_is_preserved': 'POSIX mode assertion; Windows uses ACL inheritance',
    'test_zip_slip_is_rejected': 'Windows ZipInfo constructor rewrites backslashes; raw malicious names tested separately',
    'test_missing_folder_is_reported_not_shown_as_empty': 'Exact English POSIX error text',
    'test_default_manager_prompt_once': 'xdg-mime integration',
    'test_default_manager_failure_can_retry': 'xdg-mime integration',
    'test_failed_online_disconnect_releases_scheduler_in_gui_thread': 'fusermount subprocess fixture',
    'test_help_is_nonmodal_reused_and_links_to_offline_chapter': 'Linux handbook title assertion',
}


def pytest_collection_modifyitems(items):
    for item in items:
        reason = LINUX_ONLY.get(item.name.split('[')[0])
        if reason:
            item.add_marker(pytest.mark.skip(reason=reason))
