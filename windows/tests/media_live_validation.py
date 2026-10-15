"""Opt-in codec/playback/seek/restart matrix using real Qt media decoding.

Uses generated media only, muted audio, disposable preferences, and one bounded
process per codec. It does not read or alter the user's open application.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[2]


def probe(path, state):
    sys.path.insert(0, str(REPO / 'linux'))
    from opencommander.platform_support import initialize
    initialize()
    from PySide6.QtWidgets import QApplication
    from PySide6.QtMultimedia import QMediaPlayer
    from PySide6.QtTest import QTest
    from opencommander.ui import MainWindow
    from opencommander.filesystem import Entry
    app = QApplication([])
    main = MainWindow(state, path.parent, path.parent)
    def wait(predicate, seconds=8):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            app.processEvents()
            if predicate():
                return
            QTest.qWait(10)
        raise AssertionError('Media operation timed out')
    main.open_entry(Entry(path.name, path, False, path.stat().st_size))
    viewer = main.preview_dialog
    viewer.audio.setMuted(True)
    stage = 'metadata'
    try:
        wait(lambda: viewer.player.duration() > 0 or viewer.player.error() != QMediaPlayer.NoError)
        assert viewer.player.error() == QMediaPlayer.NoError, viewer.player.errorString()
        stage = 'initial playback'
        wait(lambda: viewer.player.position() > 100)
        if path.suffix in ('.mp4', '.avi', '.webm'):
            wait(lambda: viewer.video.videoSink().videoFrame().isValid())
        stage = 'pause'
        viewer.player.pause()
        wait(lambda: viewer.player.playbackState() == QMediaPlayer.PausedState)
        stage = 'seek'
        viewer.player.setPosition(1500)
        wait(lambda: abs(viewer.player.position() - 1500) < 300)
        stage = 'resume'
        viewer.player.play()
        wait(lambda: viewer.player.position() > 1600)
        stage = 'restart'
        viewer.player.stop()
        wait(lambda: viewer.player.playbackState() == QMediaPlayer.StoppedState)
        viewer.player.play()
        wait(lambda: 100 < viewer.player.position() < 1400)
        result = dict(status='pass', file=path.name, duration_ms=viewer.player.duration(),
                      playback=True, seek=True, pause_resume=True, restart=True,
                      decoded_video_frame=path.suffix in ('.mp4', '.avi', '.webm'))
    except Exception as error:
        result = dict(status='failed', file=path.name, stage=stage, error=str(error), qt_error=viewer.player.errorString(),
                      position=viewer.player.position(), duration=viewer.player.duration(),
                      state=str(viewer.player.playbackState()), media_status=str(viewer.player.mediaStatus()))
    finally:
        viewer.shutdown()
        viewer.close()
        main.close()
        wait(lambda: not main.isVisible() and not main.tasks)
    print('RESULT:' + json.dumps(result), flush=True)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--probe':
        probe(Path(sys.argv[2]), Path(sys.argv[3]))
        return
    ffmpeg = next((REPO / 'windows/.venv/Lib/site-packages/imageio_ffmpeg/binaries').glob('*.exe'))
    base = REPO / 'windows/build/media-fixtures' / str(time.time_ns())
    base.mkdir(parents=True)
    cases = [('wave.wav', 'pcm_s16le'), ('mp3.mp3', 'libmp3lame'), ('aac.m4a', 'aac'),
             ('flac.flac', 'flac'), ('vorbis.ogg', 'libvorbis'), ('opus.opus', 'libopus'), ('wma.wma', 'wmav2'),
             ('h264.mp4', 'libx264'), ('mpeg4.avi', 'mpeg4'), ('vp9.webm', 'libvpx-vp9'), ('hevc.mp4', 'libx265')]
    results = []
    for filename, codec in cases:
        path = base / filename
        video = path.suffix in ('.mp4', '.avi', '.webm')
        command = [str(ffmpeg), '-v', 'error', '-f', 'lavfi', '-i',
                   'testsrc2=size=160x90:rate=15:duration=3' if video else 'sine=frequency=440:duration=3',
                   '-c:v' if video else '-c:a', codec]
        if video:
            command += ['-pix_fmt', 'yuv420p']
        if codec == 'libx265':
            command += ['-x265-params', 'pools=1:frame-threads=1:log-level=error', '-tag:v', 'hvc1']
        subprocess.run([*command, str(path)], capture_output=True, check=True, timeout=30)
        environment = dict(os.environ, QT_QPA_PLATFORM='windows', PYTHONUTF8='1', LANG='de_CH.UTF-8')
        completed = subprocess.run([sys.executable, __file__, '--probe', str(path), str(base / (codec + '-profile'))],
            env=environment, capture_output=True, text=True, encoding='utf-8', timeout=25,
            creationflags=subprocess.CREATE_NO_WINDOW)
        markers = [line[7:] for line in completed.stdout.splitlines() if line.startswith('RESULT:')]
        result = json.loads(markers[-1]) if markers else dict(status='failed', file=filename, error='Media probe exited without a result')
        results.append(result)
        print(json.dumps(result), flush=True)
        (REPO / 'windows/build/media-live-results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    if any(row['status'] != 'pass' for row in results):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
