"""Bounded asynchronous thumbnails and an in-app image/audio/video browser."""
from collections import OrderedDict
from pathlib import Path
import shutil
import subprocess
import json
import tempfile
import threading
import time

from PySide6.QtCore import Qt, QSize, QUrl, QThreadPool
from PySide6.QtGui import QImageReader, QImage, QPixmap, QIcon, QShortcut, QKeySequence
from PySide6.QtWidgets import (QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
                              QStackedWidget, QSlider, QMessageBox, QProgressBar)
from PySide6.QtMultimedia import QMediaPlayer, QAudioOutput
from PySide6.QtMultimediaWidgets import QVideoWidget
from .desktop import host_environment

IMAGES = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tif', '.tiff', '.svg', '.heic', '.avif'}
VIDEOS = {'.mp4', '.mov', '.mkv', '.webm', '.avi', '.m4v', '.mpeg', '.mpg'}
AUDIO = {'.mp3', '.wav', '.ogg', '.flac', '.m4a', '.aac', '.opus', '.wma'}


def media_kind(path):
    suffix = Path(path).suffix.lower()
    if suffix in IMAGES or suffix.lstrip('.') in {bytes(x).decode().lower() for x in QImageReader.supportedImageFormats()}:
        return 'image'
    return 'video' if suffix in VIDEOS else 'audio' if suffix in AUDIO else None


def read_image(path, size):
    reader = QImageReader(str(path))
    reader.setAllocationLimit(64)
    reader.setAutoTransform(True)
    original = reader.size()
    if original.isValid() and (original.width() > size.width() or original.height() > size.height()):
        reader.setScaledSize(original.scaled(size, Qt.KeepAspectRatio))
    image = reader.read()
    if image.isNull():
        raise ValueError(reader.errorString())
    return image.scaled(size, Qt.KeepAspectRatio, Qt.SmoothTransformation)



def download_online(entry, target, cancel, report=lambda *_: None, *, limit=2 * 1024**3, timeout=900):
    """Isolate remote reads in a cancellable process; preserve the file suffix for playback."""
    if entry.size > limit:
        raise ValueError(f'Online-Medium zu groß / Online media too large (limit {limit // 1024**2} MiB)')
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    request = json.dumps(dict(source=str(entry.path), target=str(target), limit=limit))
    command = ['/usr/bin/python3', str(Path(__file__).with_name('media_fetch.py'))]
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          env=host_environment()) as process:
        deadline = time.monotonic() + timeout
        activity = time.monotonic()
        count = -1
        first = True
        try:
            while True:
                if cancel.is_set():
                    raise RuntimeError('Abgebrochen / Cancelled')
                if time.monotonic() > deadline or time.monotonic() - activity > 30:
                    raise TimeoutError('Online-Medium: Zeitüberschreitung / Online media timed out')
                try:
                    output, _ = process.communicate(input=request.encode() if first else None, timeout=0.1)
                    break
                except subprocess.TimeoutExpired as waiting:
                    first = False
                    lines = (waiting.output or b'').split(b'\n')
                    if len(lines) > 1:
                        value = json.loads(lines[-2])
                        current = value.get('bytes', 0)
                        if current != count:
                            count = current
                            activity = time.monotonic()
                            report(count, entry.size)
            values = [json.loads(line) for line in output.splitlines()]
            if process.returncode or not values or not values[-1].get('done'):
                raise RuntimeError(values[-1].get('error', 'Online media download failed') if values else 'Online media download failed')
            report(values[-1]['bytes'], entry.size)
            if cancel.is_set():
                raise RuntimeError('Abgebrochen / Cancelled')
            return target
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()


def online_image(entry, size, cancel, report=lambda *_: None):
    """Sequential bounded download, then decode locally (no remote seeks)."""
    limit = (32 if size.width() <= 96 else 128) * 1024**2
    if entry.size > limit:
        raise ValueError(f'Online-Bild zu groß / Online image too large (limit {limit // 1024**2} MiB)')
    with tempfile.TemporaryDirectory(prefix='opencommander-image-') as temp:
        target = download_online(entry, Path(temp) / 'image', cancel, report, limit=limit, timeout=180)
        return read_image(target, size)


def thumbnail(path, kind):
    if kind == 'image':
        return read_image(path, QSize(96, 64))
    if kind == 'video' and shutil.which('ffmpeg'):
        result = subprocess.run(['ffmpeg', '-v', 'error', '-nostdin', '-threads', '1',
                                 '-i', str(path), '-frames:v', '1', '-vf',
                                 'scale=96:64:force_original_aspect_ratio=decrease',
                                 '-threads', '1', '-f', 'image2pipe', '-vcodec', 'png', '-'],
                                capture_output=True, timeout=8, check=True, env=host_environment())
        return QImage.fromData(result.stdout)
    return QImage()


class ThumbnailCache:
    def __init__(self, main):
        self.main = main
        self.pool = QThreadPool(main)
        self.pool.setMaxThreadCount(2)
        self.cache = OrderedDict()
        self.pending = set()
        self.remote_jobs = {}
        self.failures = {}

    def get(self, entry, model, row):
        if getattr(self.main, "closing", False):
            return None
        kind = media_kind(entry.name)
        remote = getattr(model.pane, 'remote', False)
        if (remote and kind != 'image') or entry.directory or entry.error or entry.member or kind not in ('image', 'video'):
            return None
        key = (str(entry.path), entry.size, entry.modified)
        if key in self.cache and self.cache[key] is None and time.monotonic() >= self.failures.get(key, float('inf')):
            self.cache.pop(key)
            self.failures.pop(key, None)
        if key in self.cache:
            self.cache.move_to_end(key)
            return self.cache[key]
        # Only visible cells request icons; never queue an entire directory.
        if key in self.pending or len(self.pending) >= 8 or (remote and len(self.remote_jobs) >= 2):
            return None
        from .ui import Task
        self.pending.add(key)
        cancel = threading.Event()
        pane = model.pane
        if remote:
            self.remote_jobs[key] = (pane, cancel)
        task = Task(lambda: online_image(entry, QSize(96, 64), cancel,
                         lambda count, total: task.signals.progress.emit(min(99, count * 100 // total) if total else 0, entry.name))
                    if remote else thumbnail(entry.path, kind))
        if remote:
            task.signals.progress.connect(lambda percent, name: pane.thumbnail_status.setText(
                f'Vorschaubilder laden / Loading thumbnails: {percent}% · {name}') if not cancel.is_set() else None, Qt.QueuedConnection)
        self.main.tasks.add(task)
        def done(image, error):
            self.pending.discard(key)
            self.remote_jobs.pop(key, None)
            if remote and not any(owner is pane for owner, _ in self.remote_jobs.values()):
                pane.thumbnail_status.clear()
            self.main.tasks.discard(task)
            if not cancel.is_set():
                self.cache[key] = QIcon(QPixmap.fromImage(image)) if not error and not image.isNull() else None
                if error:
                    self.failures[key] = time.monotonic() + 30
            while len(self.cache) > 256:
                evicted, _ = self.cache.popitem(last=False)
                self.failures.pop(evicted, None)
            # A changed directory/sort must not attach the image to the old row.
            for visible_pane in self.main.panes:
                visible_pane.table.viewport().update()
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.pool.start(task)
        return None

    def cancel_remote(self, pane=None):
        for owner, cancel in self.remote_jobs.values():
            if pane is None or owner is pane:
                cancel.set()
        if pane is not None:
            pane.thumbnail_status.clear()


class MediaViewer(QDialog):
    def __init__(self, main, entries, index):
        super().__init__(main)
        self.setAttribute(Qt.WA_DeleteOnClose)
        self.main, self.entries, self.index = main, entries, index
        self.generation = 0
        self.closed = False
        self.load_cancel = threading.Event()
        self.current_image = QImage()
        self.media_cache = None
        self.resize(1040, 760)
        layout = QVBoxLayout(self)
        self.caption = QLabel()
        layout.addWidget(self.caption)
        self.stack = QStackedWidget()
        self.image_label = QLabel()
        self.image_label.setAlignment(Qt.AlignCenter)
        self.image_label.setMinimumSize(1, 1)
        self.stack.addWidget(self.image_label)
        self.video = QVideoWidget()
        self.stack.addWidget(self.video)
        layout.addWidget(self.stack, 1)
        self.message = QLabel()
        self.message.setWordWrap(True)
        layout.addWidget(self.message)
        self.download_progress = QProgressBar()
        self.download_progress.setRange(0, 0)
        self.download_progress.hide()
        layout.addWidget(self.download_progress)
        self.cancel_download = QPushButton('Laden abbrechen' if main.language == 'de' else 'Cancel download')
        self.cancel_download.hide()
        self.cancel_download.clicked.connect(self.load_cancelled)
        layout.addWidget(self.cancel_download)
        self.player = QMediaPlayer(self)
        self.audio = QAudioOutput(self)
        self.audio.setVolume(0.6)
        self.player.setAudioOutput(self.audio)
        self.player.setVideoOutput(self.video)
        self.player.errorOccurred.connect(lambda *args: self.message.setText(self.player.errorString()))
        self.player.playbackStateChanged.connect(lambda state: self.play.setText('Ⅱ' if state == QMediaPlayer.PlayingState else '▶'))
        controls = QHBoxLayout()
        self.previous = QPushButton('←')
        self.previous.setAccessibleName('Previous media')
        self.delete_button = QPushButton('In Papierkorb' if main.language == 'de' else 'Move to trash')
        self.delete_button.setObjectName('previewTrash')
        self.delete_button.clicked.connect(self.trash_current)
        self.deleting = False
        self.next = QPushButton('→')
        self.next.setAccessibleName('Next media')
        self.play = QPushButton('▶')
        self.previous.clicked.connect(lambda: self.step(-1))
        self.next.clicked.connect(lambda: self.step(1))
        self.play.clicked.connect(self.toggle_play)
        self.seek = QSlider(Qt.Horizontal)
        self.seek.setAccessibleName('Playback position')
        self.seek.sliderMoved.connect(self.player.setPosition)
        self.player.durationChanged.connect(lambda duration: self.seek.setRange(0, min(duration, 2147483647)))
        self.player.positionChanged.connect(lambda position: self.seek.setValue(position) if not self.seek.isSliderDown() else None)
        for widget in (self.previous, self.play, self.seek, self.next, self.delete_button):
            controls.addWidget(widget)
        layout.addLayout(controls)
        for key, callback in [('Left', lambda: self.step(-1)), ('Right', lambda: self.step(1)), ('Space', self.toggle_play), ('Delete', self.trash_current)]:
            shortcut = QShortcut(QKeySequence(key), self)
            shortcut.setContext(Qt.WindowShortcut)
            shortcut.activated.connect(callback)
        self.load()

    def step(self, delta):
        if self.deleting:
            return
        index = self.index + delta
        if 0 <= index < len(self.entries):
            self.index = index
            self.load()

    def load(self):
        from .ui import Task
        self.load_cancel.set()
        self.load_cancel = threading.Event()
        cancel = self.load_cancel
        self.generation += 1
        generation = self.generation
        entry = self.entries[self.index]
        kind = media_kind(entry.name)
        from .filesystem import remote_location
        remote = not entry.member and remote_location(entry.path)
        remote_image = kind == 'image' and remote
        remote_playback = kind in ('video', 'audio') and remote
        self.download_progress.setVisible(remote)
        self.cancel_download.setVisible(remote)
        self.cancel_download.setEnabled(True)
        self.download_progress.setRange(0, 0)
        self.delete_button.setEnabled(not entry.member and not self.main.busy)
        self.player.stop()
        self.player.setSource(QUrl())
        self.clear_media_cache()
        cache = tempfile.TemporaryDirectory(prefix='opencommander-media-') if remote_playback else None
        self.media_cache = cache
        started = time.monotonic()
        def report(count, total):
            elapsed = max(0.1, time.monotonic() - started)
            label = f'{count / 1024**2:.1f} / {total / 1024**2:.1f} MiB · {elapsed:.0f}s · {count / elapsed / 1024**2:.1f} MiB/s'
            task.signals.progress.emit(min(99, count * 100 // total) if total else 0, label)
        self.current_image = QImage()
        self.image_label.clear()
        self.stack.setCurrentWidget(self.image_label)
        self.message.setText(('Online-Medium wird zwischengespeichert. Wiedergabe startet nach dem Laden …' if self.main.language == 'de' else 'Caching online media. Playback starts after download …') if remote_playback else ('Laden …' if self.main.language == 'de' else 'Loading …'))
        self.setWindowTitle(entry.name)
        self.caption.setText(f'{self.index + 1} / {len(self.entries)}  ·  {entry.name}')
        self.previous.setEnabled(self.index > 0)
        self.next.setEnabled(self.index + 1 < len(self.entries))
        self.play.setEnabled(False)
        self.seek.setEnabled(False)
        self.play.setVisible(kind == 'video')
        self.seek.setVisible(kind == 'video')
        def work():
            if self.closed or generation != self.generation:
                return None
            if remote_image:
                return entry.path, online_image(entry, QSize(2560, 1600), cancel, report)
            if remote_playback:
                try:
                    path = download_online(entry, Path(cache.name) / ('preview' + entry.path.suffix), cancel, report)
                    return path, None
                except Exception:
                    cache.cleanup()
                    raise
            path = self.main.materialize(entry)
            return path, read_image(path, QSize(2560, 1600)) if kind == 'image' else None
        task = Task(work)
        def downloading(percent, label):
            if not self.closed and generation == self.generation:
                self.download_progress.setRange(0, 100 if entry.size else 0)
                self.download_progress.setValue(percent)
                self.message.setText(('Medium herunterladen: ' if self.main.language == 'de' else 'Downloading media: ') + f'{percent}% · ' + label)
        task.signals.progress.connect(downloading, Qt.QueuedConnection)
        self.main.tasks.add(task)
        def done(value, error):
            self.main.tasks.discard(task)
            if self.closed or generation != self.generation:
                return
            self.download_progress.hide()
            self.cancel_download.hide()
            self.message.setText(str(error) if error else '')
            if error or value is None:
                return
            path, image = value
            if kind == 'image':
                self.current_image = image
                self.fit_image()
            else:
                self.stack.setCurrentWidget(self.video if kind == 'video' else self.image_label)
                if kind == 'audio':
                    self.image_label.setText('♫\n' + entry.name)
                self.play.setEnabled(True)
                self.seek.setEnabled(True)
                self.player.setSource(QUrl.fromLocalFile(str(path)))
                self.player.play()
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.main.pool.start(task)

    def trash_current(self):
        if self.closed or self.deleting or self.main.busy:
            return
        entry = self.entries[self.index]
        if entry.member:
            self.message.setText(self.main.tr_key('zip_readonly'))
            return
        if QMessageBox.question(self, self.main.tr_key('trash'),
                self.main.tr_key('confirm_trash') + '\n' + str(entry.path),
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No) != QMessageBox.Yes:
            return
        self.deleting = True
        self.load_cancel.set()
        self.generation += 1
        self.player.stop()
        self.player.setSource(QUrl())
        self.delete_button.setEnabled(False)
        self.previous.setEnabled(False)
        self.next.setEnabled(False)
        def finished(error):
            self.main.operation_finished.disconnect(finished)
            self.deleting = False
            if self.closed:
                return
            if error:
                self.load()
                self.message.setText(str(error))
                return
            self.entries = [item for item in self.entries if item.path != entry.path]
            if not self.entries:
                self.close()
                return
            self.index = min(self.index, len(self.entries) - 1)
            self.load()
        self.main.operation_finished.connect(finished)
        self.main.run_operation(lambda: self.main.engine.trash([entry.path]))

    def fit_image(self):
        if not self.current_image.isNull():
            self.image_label.setPixmap(QPixmap.fromImage(self.current_image).scaled(
                self.stack.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation))

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.fit_image()

    def toggle_play(self):
        if self.play.isEnabled():
            self.player.pause() if self.player.playbackState() == QMediaPlayer.PlayingState else self.player.play()

    def load_cancelled(self):
        self.load_cancel.set()
        self.cancel_download.setEnabled(False)
        self.message.setText('Laden wird abgebrochen …' if self.main.language == 'de' else 'Cancelling download …')

    def clear_media_cache(self):
        if self.media_cache is not None:
            self.media_cache.cleanup()
            self.media_cache = None

    def shutdown(self):
        self.closed = True
        self.load_cancel.set()
        self.generation += 1
        self.player.stop()
        self.player.setSource(QUrl())
        self.clear_media_cache()

    def closeEvent(self, event):
        self.shutdown()
        super().closeEvent(event)

    def reject(self):
        self.shutdown()
        super().reject()
