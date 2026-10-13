import shutil
import subprocess
import pytest
from PySide6.QtCore import QSize
from PySide6.QtGui import QImage, QColor
from opencommander.media import read_image, thumbnail, media_kind


def test_thumbnail_dimensions_and_corrupt_file(tmp_path):
    path = tmp_path / 'wide.PNG'
    image = QImage(1200, 600, QImage.Format_RGB32)
    image.fill(QColor('green'))
    image.save(str(path))
    result = thumbnail(path, 'image')
    assert result.width() == 96 and result.height() == 48
    assert media_kind(path) == 'image'
    assert media_kind('MOVIE.MP4') == 'video'
    assert media_kind('music.flac') == 'audio'
    path.write_bytes(b'bad image')
    with pytest.raises(ValueError):
        read_image(path, QSize(96, 64))


@pytest.mark.skipif(not shutil.which('ffmpeg'), reason='ffmpeg is optional for video thumbnails')
def test_video_thumbnail(tmp_path):
    path = tmp_path / 'sample.mp4'
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=160x90:d=0.2',
                    '-c:v', 'mpeg4', str(path)], check=True, timeout=10)
    result = thumbnail(path, 'video')
    assert not result.isNull()
    assert result.width() <= 96 and result.height() <= 64


def test_online_jpeg_downloads_sequentially_and_decodes(tmp_path):
    import threading
    from opencommander.media import online_image
    from opencommander.filesystem import Entry
    path = tmp_path / 'photo.JPG'
    image = QImage(640, 320, QImage.Format_RGB32)
    image.fill(QColor('blue'))
    assert image.save(str(path))
    entry = Entry(path.name, path, False, path.stat().st_size)
    progress = []
    result = online_image(entry, QSize(96, 64), threading.Event(), lambda count, total: progress.append((count, total)))
    assert result.size() == QSize(96, 48)
    assert progress[-1] == (entry.size, entry.size)


def test_online_image_cancel_interrupts_blocked_read(tmp_path):
    import os
    import threading
    import time
    from opencommander.media import online_image
    from opencommander.filesystem import Entry
    fifo = tmp_path / 'blocked.jpg'
    os.mkfifo(fifo)
    cancel = threading.Event()
    errors = []
    def read():
        try:
            online_image(Entry(fifo.name, fifo, False), QSize(96, 64), cancel)
        except Exception as error:
            errors.append(error)
    thread = threading.Thread(target=read, daemon=True)
    thread.start()
    time.sleep(0.15)
    cancel.set()
    thread.join(2)
    assert not thread.is_alive()
    assert isinstance(errors[0], RuntimeError)
    assert 'Cancelled' in str(errors[0])


def test_online_thumbnail_rejects_oversized_file_before_download(tmp_path):
    import threading
    from opencommander.media import online_image
    from opencommander.filesystem import Entry
    entry = Entry('large.jpg', tmp_path / 'absent.jpg', False, 33 * 1024**2)
    with pytest.raises(ValueError, match='too large'):
        online_image(entry, QSize(96, 64), threading.Event())


def test_online_media_cache_preserves_bytes_permissions_and_actual_limit(tmp_path):
    import threading
    from opencommander.media import download_online
    from opencommander.filesystem import Entry
    source = tmp_path / 'movie.mp4'
    source.write_bytes(b'video payload' * 200000)
    entry = Entry(source.name, source, False, source.stat().st_size)
    target = tmp_path / 'preview.mp4'
    progress = []
    assert download_online(entry, target, threading.Event(), lambda *args: progress.append(args)) == target
    assert target.read_bytes() == source.read_bytes()
    assert target.stat().st_mode & 0o777 == 0o600
    assert progress[-1] == (entry.size, entry.size)
    # A provider's advertised size must not bypass the actual byte bound.
    entry.size = 0
    with pytest.raises(RuntimeError, match='Could not download'):
        download_online(entry, tmp_path / 'too-large.mp4', threading.Event(), limit=1024)
