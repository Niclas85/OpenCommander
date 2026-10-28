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
    # The shared suites create small Python backends with POSIX shebangs.
    # Windows cannot execute those directly; preserve their argv through Python.
    import subprocess
    original_popen = subprocess.Popen
    def launch_fixture(command, *args, **kwargs):
        if isinstance(command, (list, tuple)) and command:
            executable = Path(command[0])
            if executable.is_absolute() and executable.is_relative_to(tmp_path):
                try:
                    with executable.open('rb') as stream:
                        python_fixture = stream.read(64).startswith(b'#!/usr/bin/python3')
                except OSError:
                    python_fixture = False
                if python_fixture:
                    command = [sys.executable, str(executable), *command[1:]]
        return original_popen(command, *args, **kwargs)
    monkeypatch.setattr(subprocess, 'Popen', launch_fixture)
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
    'test_pending_or_present_local_cache_never_allows_remote_proof': '/proc rclone FUSE writeback cache; Windows uses write-through WinFsp mounts',
    'test_external_mount_discovery_keeps_namespace_and_never_returns_secrets': '/proc mountinfo discovery; native Windows process discovery covered separately',
    'test_helper_uses_stdin_without_shell': 'GIO subprocess helper; frozen Windows helper verified by package checks',
    'test_helper_failure_reported': 'GIO authentication callback; Windows helper has separate error handling',
    'test_cloud_locations_include_icloud_and_custom_dropbox': '/proc discovery fixture; native Windows discovery covered separately',
    'test_keyring_payload_not_in_command': 'Linux Secret Service subprocess; native Windows credentials tested separately',
    'test_rclone_detection_respects_other_nested_mounts': 'Linux mountinfo identity; Windows namespace identity covered separately',
    'test_rclone_rename_fails_closed_when_target_cannot_be_checked': 'Linux FUSE mounted-path fixture; native Windows non-replacing rename covered separately',
    'test_gvfs_provider_detection_limits_rename_to_same_share': 'GVFS share namespaces are Linux-only; Windows uses UNC namespaces',
    'test_parallel_mount_requests_launch_one_daemon': 'FUSE daemon subprocess fixture; Windows uses authenticated WinFsp processes',
    'test_new_mount_limits_retry_wait_without_writeback': 'FUSE command fixture; WinFsp live tests verify bounded disconnect and write-through I/O',
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
