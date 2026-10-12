from __future__ import annotations

from datetime import datetime
from pathlib import Path, PurePosixPath
import json
import os
import shutil
import tempfile
import time
import threading
import zipfile

from PySide6.QtCore import (Qt, Signal, QObject, QRunnable, QThreadPool, QAbstractTableModel,
    QModelIndex, QSortFilterProxyModel, QUrl, QMimeData, QTimer, QDir, QFileSystemWatcher,
    QSettings, QStandardPaths, QSize, QPoint, QItemSelectionModel, QEvent)
from PySide6.QtGui import (QAction, QKeySequence, QDrag, QDesktopServices, QImageReader,
    QPixmap, QIcon, QColor, QPainter, QPen)
from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QLineEdit, QSplitter, QTreeView, QTableView, QFileSystemModel,
    QAbstractItemView, QHeaderView, QComboBox, QProgressBar, QToolBar, QMenu, QFileDialog,
    QInputDialog, QMessageBox, QDialog, QTextEdit, QScrollArea, QDockWidget, QListWidget,
    QListWidgetItem, QStyle, QFrame, QCheckBox)

from .filesystem import listing, archive_listing, mounted_locations, cloud_locations, remote_location, Entry
from .archives import is_archive, open_archive
from .operations import FileEngine, SafetyError, Cancelled, exists, unique_path, checked_members
from .i18n import text
from . import __version__
from .media import media_kind, ThumbnailCache, MediaViewer
from .controls import ModeToggle
from .formatting import human_duration
from .location_preferences import load_preferences, configured_locations
from .places_ui import PlaceButton, load_order, ordered_places, provider_icon
from shiboken6 import isValid


def human_size(value):
    for unit in ('B', 'KiB', 'MiB', 'GiB', 'TiB'):
        if value < 1024 or unit == 'TiB':
            return f'{value:.0f} {unit}' if unit == 'B' else f'{value:.1f} {unit}'
        value /= 1024


class TaskSignals(QObject):
    result = Signal(object, object)
    progress = Signal(int, str)
    metrics = Signal(object)


class Task(QRunnable):
    def __init__(self, work):
        super().__init__()
        self.work = work
        self.signals = TaskSignals()

    def run(self):
        try:
            value = self.work()
        except Exception as error:
            self.signals.result.emit(None, error)
        else:
            self.signals.result.emit(value, None)


class EntryModel(QAbstractTableModel):
    def __init__(self, pane):
        super().__init__(pane)
        self.pane = pane
        self.entries = []
        self.formatted = {}
        style = QApplication.style()
        self.folder_icon = QIcon(style.standardIcon(QStyle.SP_DirIcon).pixmap(24, 24))
        self.file_icon = QIcon(style.standardIcon(QStyle.SP_FileIcon).pixmap(24, 24))
        self.link_icon = QIcon(style.standardIcon(QStyle.SP_FileLinkIcon).pixmap(24, 24))

    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self.entries)

    def flags(self, index):
        flags = super().flags(index)
        if self.pane.archive:
            return flags
        if not index.isValid():
            return flags | Qt.ItemIsDropEnabled
        entry = self.entries[index.row()]
        if not entry.error:
            flags |= Qt.ItemIsDragEnabled
        if entry.directory:
            flags |= Qt.ItemIsDropEnabled
        return flags

    def supportedDragActions(self):
        return Qt.CopyAction

    def columnCount(self, parent=QModelIndex()):
        return 4

    def headerData(self, section, orientation, role=Qt.DisplayRole):
        if orientation == Qt.Horizontal and role == Qt.DisplayRole:
            return self.pane.main.tr_key(('name', 'size', 'type', 'modified')[section])

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid():
            return None
        item = self.entries[index.row()]
        column = index.column()
        if role == Qt.UserRole:
            if column == 0:
                return item.name.casefold()
            if column == 1:
                return item.size
            if column == 2:
                return '0' if item.directory else Path(item.name).suffix
            return item.modified
        if role == Qt.ForegroundRole and column == 0:
            dark = self.pane.main.dark
            if item.error:
                return QColor('#ff919c' if dark else '#b42338')
            if item.directory:
                return QColor('#88baff' if dark else '#185bb5')
            suffix = Path(item.name).suffix.lower()
            if suffix in ('.zip', '.tar', '.gz', '.7z', '.rar'):
                return QColor('#f1c36d' if dark else '#885400')
            if suffix in ('.png', '.jpg', '.jpeg', '.svg', '.mp4', '.mp3', '.webp'):
                return QColor('#cfadff' if dark else '#753bb0')
        if role == Qt.DecorationRole and column == 0:
            thumbnail = self.pane.main.thumbnails.get(item, self, index.row())
            if thumbnail is not None:
                return thumbnail
            return self.link_icon if item.link else self.folder_icon if item.directory else self.file_icon
        if role == Qt.TextAlignmentRole and column == 1:
            return int(Qt.AlignRight | Qt.AlignVCenter)
        if role == Qt.ToolTipRole:
            return str(item.path) + (f'!/{item.member}' if item.member else '') + ('\n' + item.error if item.error else '')
        if role != Qt.DisplayRole:
            return None
        if item.error:
            return (item.name, '—', '⚠', '—')[column]
        if column == 0:
            return item.name
        key = (index.row(), column, self.pane.main.language)
        if key not in self.formatted:
            if column == 1:
                value = '—' if item.directory else human_size(item.size)
            elif column == 2:
                kind = self.pane.main.tr_key('link' if item.link else 'directory' if item.directory else 'file')
                value = kind if item.directory or item.link else Path(item.name).suffix.removeprefix('.').upper() or kind
            else:
                try:
                    value = datetime.fromtimestamp(item.modified).strftime('%d.%m.%Y %H:%M') if item.modified else '—'
                except (ValueError, OverflowError, OSError):
                    value = '—'
            self.formatted[key] = value
        return self.formatted[key]

    def replace(self, entries):
        self.beginResetModel()
        self.entries = entries
        self.formatted.clear()
        self.endResetModel()


class EntryProxy(QSortFilterProxyModel):
    def lessThan(self, left, right):
        a, b = self.sourceModel().entries[left.row()], self.sourceModel().entries[right.row()]
        if a.directory != b.directory:
            return a.directory if self.sortOrder() == Qt.AscendingOrder else b.directory
        return super().lessThan(left, right)


class FileTable(QTableView):
    def __init__(self, pane):
        super().__init__(pane)
        self.pane = pane
        self.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.setDragEnabled(True)
        self.setAcceptDrops(True)
        self.setDropIndicatorShown(True)
        self.setDragDropMode(QAbstractItemView.DragDrop)
        self.setAlternatingRowColors(True)
        self.setShowGrid(False)
        self.setSortingEnabled(True)
        self.setHorizontalScrollMode(QAbstractItemView.ScrollPerPixel)
        self.verticalHeader().hide()
        self.verticalHeader().setDefaultSectionSize(52)
        self.setIconSize(QSize(72, 44))
        self.setContextMenuPolicy(Qt.CustomContextMenu)
        self.customContextMenuRequested.connect(self.context_menu)

    def focusInEvent(self, event):
        self.pane.main.activate(self.pane)
        super().focusInEvent(event)

    def startDrag(self, supported):
        entries = self.pane.selected()
        if self.pane.archive or (self.pane.main.busy and not self.pane.main.operation_running) or not entries:
            return
        mime = QMimeData()
        mime.setUrls([QUrl.fromLocalFile(str(e.path)) for e in entries])
        drag = QDrag(self)
        drag.setMimeData(mime)
        preview = QPixmap(300, 64)
        preview.fill(Qt.transparent)
        painter = QPainter(preview)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(QPen(QColor('#88baff'), 1))
        painter.setBrush(QColor('#242e40'))
        painter.drawRoundedRect(0, 0, 299, 63, 10, 10)
        icon = self.pane.main.thumbnails.cache.get((str(entries[0].path), entries[0].size, entries[0].modified))
        if icon is None:
            icon = self.pane.model.folder_icon if entries[0].directory else self.pane.model.file_icon
        painter.drawPixmap(10, 10, icon.pixmap(42, 42))
        painter.setPen(QColor('#e8eef9'))
        font = painter.font()
        font.setBold(True)
        painter.setFont(font)
        painter.drawText(62, 25, painter.fontMetrics().elidedText(entries[0].name, Qt.ElideMiddle, 225))
        font.setBold(False)
        painter.setFont(font)
        mode = self.pane.main.mode.currentData() == 'move'
        label = ('Verschieben' if mode else 'Kopieren') if self.pane.main.language == 'de' else ('Move' if mode else 'Copy')
        painter.drawText(62, 47, f'{label} · {len(entries)}')
        painter.end()
        drag.setPixmap(preview)
        drag.setHotSpot(QPoint(20, 20))
        drag.exec(Qt.CopyAction)  # The receiver owns transfers; never request a second deletion.

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls() and not self.pane.archive and not (self.pane.main.busy and not self.pane.main.operation_running):
            event.acceptProposedAction()
        else:
            event.ignore()

    def dragMoveEvent(self, event):
        self.dragEnterEvent(event)

    def dropEvent(self, event):
        if self.pane.archive or (self.pane.main.busy and not self.pane.main.operation_running):
            event.ignore()
            return
        entry = self.pane.entry_at(self.indexAt(event.position().toPoint()))
        directory = entry.path if entry and entry.directory else self.pane.directory
        self.pane.main.drop_urls(event.mimeData().urls(), directory)
        event.setDropAction(Qt.CopyAction)
        event.accept()

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key_Return, Qt.Key_Enter):
            self.pane.main.open_selected()
        elif event.key() == Qt.Key_Space and not event.modifiers():
            self.pane.main.preview_selected()
        else:
            super().keyPressEvent(event)

    def context_menu(self, point):
        index = self.indexAt(point)
        if not index.isValid():
            self.pane.main.activate(self.pane)
            self.clearSelection()
            menu = QMenu(self)
            if not self.pane.archive:
                menu.addAction(self.pane.main.actions['new_folder'])
                paste = menu.addAction('Einfügen' if self.pane.main.language == 'de' else 'Paste')
                mime = QApplication.clipboard().mimeData()
                paste.setEnabled(bool(mime and (mime.hasUrls() or mime.hasFormat('x-special/gnome-copied-files'))))
                paste.triggered.connect(self.pane.main.paste_clipboard)
                menu.addSeparator()
            refresh = menu.addAction(self.pane.main.tr_key('refresh'))
            refresh.triggered.connect(self.pane.refresh)
            menu.addAction(self.pane.main.actions['hidden'])
            menu.exec(self.viewport().mapToGlobal(point))
            return
        if not self.selectionModel().isRowSelected(index.row()):
            self.clearSelection()
            self.selectRow(index.row())
        self.selectionModel().setCurrentIndex(index, QItemSelectionModel.NoUpdate)
        self.pane.main.activate(self.pane)
        menu = QMenu(self)
        for key in ('open', 'open_with', 'preview', 'copy', 'move', 'rename', 'zip', 'extract', 'trash', 'info'):
            menu.addAction(self.pane.main.actions[key])
        from .cloud_actions import add_cloud_actions
        add_cloud_actions(menu, self.pane)
        menu.exec(self.viewport().mapToGlobal(point))


class FolderTree(QTreeView):
    def __init__(self, pane):
        super().__init__(pane)
        self.pane = pane
        self.setHeaderHidden(True)
        self.setAcceptDrops(True)
        self.setDragDropMode(QAbstractItemView.DropOnly)

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls() and not (self.pane.main.busy and not self.pane.main.operation_running):
            event.acceptProposedAction()
        else:
            event.ignore()

    def dragMoveEvent(self, event):
        self.dragEnterEvent(event)

    def dropEvent(self, event):
        index = self.indexAt(event.position().toPoint())
        if not index.isValid() or (self.pane.main.busy and not self.pane.main.operation_running):
            event.ignore()
            return
        self.pane.main.drop_urls(event.mimeData().urls(), Path(self.pane.tree_model.filePath(index)))
        event.setDropAction(Qt.CopyAction)
        event.accept()


class Pane(QFrame):
    def __init__(self, main, number, directory):
        super().__init__()
        self.main, self.number = main, number
        self.directory, self.archive, self.prefix = Path(directory), None, ''
        self.navigation, self.nav_index = [], -1
        self.generation = 0
        self.load_cancel = threading.Event()
        self.remote = False
        self.setObjectName('pane')
        self.setProperty('side', str(number))
        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 10, 10, 8)
        layout.setSpacing(8)
        title_row = QHBoxLayout()
        self.title = QLabel()
        self.title.setTextFormat(Qt.PlainText)
        self.title.setObjectName('paneTitle')
        title_row.addWidget(self.title)
        title_row.addStretch()
        self.selected_label = QLabel()
        self.selected_label.setObjectName('muted')
        title_row.addWidget(self.selected_label)
        layout.addLayout(title_row)
        navigation = QHBoxLayout()
        for label, hint, callback in [('‹', 'Alt+Left', lambda: self.travel(-1)),
                                      ('›', 'Alt+Right', lambda: self.travel(1)),
                                      ('↑', 'Alt+Up', self.up)]:
            button = QPushButton(label)
            button.setFixedWidth(32)
            button.setToolTip(hint)
            button.clicked.connect(callback)
            navigation.addWidget(button)
        self.path_edit = QLineEdit()
        self.path_edit.setAccessibleName(f'Path {number}')
        self.path_edit.returnPressed.connect(self.navigate_text)
        navigation.addWidget(self.path_edit, 1)
        layout.addLayout(navigation)
        splitter = QSplitter(Qt.Horizontal)
        self.tree_model = QFileSystemModel(self)
        self.tree_model.setFilter(QDir.AllDirs | QDir.NoDotAndDotDot | (QDir.Hidden if main.hidden else QDir.Filter(0)))
        self.tree_model.setRootPath('/')
        self.tree = FolderTree(self)
        self.tree.setModel(self.tree_model)
        self.tree.setRootIndex(self.tree_model.index('/'))
        for column in range(1, 4):
            self.tree.hideColumn(column)
        self.tree.clicked.connect(lambda index: self.navigate(Path(self.tree_model.filePath(index))))
        self.tree_model.directoryLoaded.connect(lambda _: self.sync_tree())
        self.tree.setMinimumWidth(150)
        self.tree.setTextElideMode(Qt.ElideNone)
        self.tree.header().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.tree.header().setStretchLastSection(False)
        splitter.addWidget(self.tree)
        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)
        self.filter = QLineEdit()
        self.filter.setClearButtonEnabled(True)
        right_layout.addWidget(self.filter)
        filter_row = QHBoxLayout()
        self.filter_hint = QLabel()
        self.filter_hint.setTextFormat(Qt.PlainText)
        self.filter_hint.setWordWrap(True)
        self.filter_hint.setObjectName('muted')
        self.clear_filter = QPushButton()
        self.clear_filter.clicked.connect(self.filter.clear)
        filter_row.addWidget(self.filter_hint, 1)
        filter_row.addWidget(self.clear_filter)
        right_layout.addLayout(filter_row)
        clear_action = QAction(self.filter)
        clear_action.setShortcut(QKeySequence('Esc'))
        clear_action.setShortcutContext(Qt.WidgetShortcut)
        clear_action.triggered.connect(self.filter.clear)
        self.filter.addAction(clear_action)
        self.model = EntryModel(self)
        self.proxy = EntryProxy(self)
        self.proxy.setSourceModel(self.model)
        self.proxy.setSortRole(Qt.UserRole)
        self.proxy.setFilterCaseSensitivity(Qt.CaseInsensitive)
        self.proxy.setFilterKeyColumn(0)
        self.filter.textChanged.connect(self.proxy.setFilterFixedString)
        self.filter.textChanged.connect(lambda _: self.selection_changed())
        self.table = FileTable(self)
        self.table.setModel(self.proxy)
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        for column, width in ((1, 90), (2, 70), (3, 125)):
            self.table.setColumnWidth(column, width)
        self.table.sortByColumn(0, Qt.AscendingOrder)
        self.table.doubleClicked.connect(lambda index: self.open_entry(self.entry_at(index)))
        self.table.selectionModel().selectionChanged.connect(self.selection_changed)
        right_layout.addWidget(self.table)
        self.message = QLabel()
        self.message.setWordWrap(True)
        self.message.setObjectName('muted')
        right_layout.addWidget(self.message)
        self.thumbnail_status = QLabel()
        self.thumbnail_status.setObjectName('muted')
        self.thumbnail_status.setWordWrap(True)
        self.thumbnail_status.setTextFormat(Qt.PlainText)
        right_layout.addWidget(self.thumbnail_status)
        loading_row = QHBoxLayout()
        self.loading_bar = QProgressBar()
        self.loading_bar.setRange(0, 0)
        self.loading_bar.hide()
        self.stop_loading = QPushButton('✕')
        self.stop_loading.setToolTip('Laden abbrechen / Cancel loading')
        self.stop_loading.clicked.connect(self.cancel_loading)
        self.stop_loading.hide()
        self.retry_loading = QPushButton('Erneut laden / Retry')
        self.retry_loading.clicked.connect(lambda: self.refresh())
        self.retry_loading.hide()
        loading_row.addWidget(self.loading_bar)
        loading_row.addWidget(self.stop_loading)
        loading_row.addWidget(self.retry_loading)
        right_layout.addLayout(loading_row)
        splitter.addWidget(right)
        splitter.setStretchFactor(1, 1)
        self.tree_splitter = splitter
        saved_sizes = main.settings.value(f'pane{number}_tree_sizes')
        if isinstance(saved_sizes, list) and len(saved_sizes) == 2:
            try:
                splitter.setSizes([max(150, int(saved_sizes[0])), max(240, int(saved_sizes[1]))])
            except (ValueError, TypeError):
                splitter.setSizes([280, 350])
        else:
            splitter.setSizes([280, 350])
        splitter.splitterMoved.connect(lambda *_: main.settings.setValue(f'pane{number}_tree_sizes', splitter.sizes()))
        layout.addWidget(splitter, 1)
        self.watcher = QFileSystemWatcher(self)
        self.refresh_timer = QTimer(self)
        self.refresh_timer.setSingleShot(True)
        self.refresh_timer.setInterval(250)
        self.refresh_timer.timeout.connect(lambda: self.refresh() if not self.main.busy else None)
        self.watcher.directoryChanged.connect(lambda _: self.refresh_timer.start())
        self.navigate(self.directory)

    def location(self):
        return (self.directory, self.archive, self.prefix)

    def navigate(self, directory, archive=None, prefix='', remember=True):
        self.main.activate(self)
        directory = Path(os.path.abspath(directory))
        previous_directory, previous_archive, previous_prefix = self.location()
        self.return_selection = None
        if archive == previous_archive and archive and previous_prefix:
            old = PurePosixPath(previous_prefix.rstrip('/'))
            if old.parent == PurePosixPath(prefix or '.'):
                self.return_selection = old.name
        elif previous_archive and not archive and directory == previous_archive.parent:
            self.return_selection = previous_archive.name
        elif not archive and not previous_archive and previous_directory != directory and previous_directory.parent == directory:
            self.return_selection = previous_directory.name
        self.directory, self.archive, self.prefix = directory, archive, prefix
        self.main.activate(self)
        if remember:
            del self.navigation[self.nav_index + 1:]
            if not self.navigation or self.navigation[-1] != self.location():
                self.navigation.append(self.location())
            self.nav_index = len(self.navigation) - 1
        self.path_edit.setText(str(archive) + '!/' + prefix if archive else str(directory))
        self.filter.clear()
        if self.watcher.directories():
            self.watcher.removePaths(self.watcher.directories())
        self.remote = remote_location(directory)
        if not self.remote:
            self.watcher.addPath(str(directory))
        self.main.settings.setValue(f'pane{self.number}', str(directory))
        self.sync_tree()
        self.refresh()

    def sync_tree(self):
        if self.remote or getattr(self.main, "closing", False):
            return
        index = self.tree_model.index(str(self.directory))
        if index.isValid():
            parent = index.parent()
            while parent.isValid():
                self.tree.expand(parent)
                parent = parent.parent()
            self.tree.setCurrentIndex(index)
            self.tree.scrollTo(index)

    def navigate_text(self):
        value = os.path.expanduser(self.path_edit.text())
        marker = value.find('!/')
        if marker >= 0 and is_archive(value[:marker]):
            archive = Path(value[:marker])
            prefix = value[marker + 2:]
            self.navigate(archive.parent, archive, prefix.rstrip('/') + '/' if prefix else '')
        else:
            self.navigate(Path(value))

    def travel(self, delta):
        index = self.nav_index + delta
        if 0 <= index < len(self.navigation):
            self.nav_index = index
            self.navigate(*self.navigation[index], remember=False)

    def up(self):
        if self.archive and self.prefix:
            prefix = str(PurePosixPath(self.prefix.rstrip('/')).parent)
            self.navigate(self.directory, self.archive, '' if prefix == '.' else prefix + '/')
        elif self.archive:
            self.navigate(self.archive.parent)
        else:
            self.navigate(self.directory.parent)

    def cancel_loading(self):
        self.load_cancel.set()
        self.generation += 1
        self.loading_bar.hide()
        self.stop_loading.hide()
        self.retry_loading.show()
        self.message.setText('Abgebrochen / Cancelled')

    def refresh(self, automatic=False):
        if getattr(self.main, "closing", False):
            return
        if not automatic:
            self.cloud_retry_count = 0
        self.main.thumbnails.cancel_remote(self)
        self.load_cancel.set()
        self.load_cancel = threading.Event()
        cancel = self.load_cancel
        self.generation += 1
        generation = self.generation
        directory, archive, prefix = self.location()
        self.message.setText(self.main.tr_key('loading'))
        if getattr(self, 'listed_location', None) != self.location():
            self.model.replace([])
        self.loading_bar.show()
        self.stop_loading.show()
        self.retry_loading.hide()
        hidden = self.main.hidden
        profile = None
        if self.remote and not archive:
            from .external_cloud import root_for
            profile = next((dict(row) for row in self.main.online_profiles + self.main.external_cloud_profiles
                            if row['kind'] in ('onedrive', 'drive', 'dropbox', 'iclouddrive') and
                            (directory == root_for(self.main, row) or
                             root_for(self.main, row) in directory.parents)), None)
        started = time.monotonic()
        timer = QTimer(self)
        timer.setInterval(250)
        def waiting():
            if generation != self.generation:
                timer.stop()
                return
            elapsed = time.monotonic() - started
            self.message.setText(f'{self.main.tr_key("loading")} · {human_duration(elapsed, self.main.language)} · {"Cloud" if profile else "Netzwerk / Network"}')
            if elapsed >= (32 if profile else 17):
                self.cancel_loading()
                self.message.setText('Verbindung antwortet nicht rechtzeitig. Erneut laden oder anderen Ordner öffnen. / Connection timed out; retry or open another folder.')
                timer.stop()
        if self.remote:
            timer.timeout.connect(waiting)
            timer.start()
        def work():
            if cancel.is_set():
                return []
            if profile:
                from .online_ui import list_cloud
                from .cloud_listing import CloudRows
                rows = list_cloud(self.main, profile, directory, cancel)
                return CloudRows([entry for entry in rows if hidden or not entry.name.startswith('.')],
                                 getattr(rows, 'warning', ''))
            return archive_listing(archive, prefix) if archive else listing(directory, hidden, cancel=cancel)
        task = Task(work)
        def done(entries, error):
            timer.stop()
            timer.deleteLater()
            if generation != self.generation:
                return
            self.loading_bar.hide()
            self.stop_loading.hide()
            warning = getattr(entries, 'warning', '')
            retryable = bool(getattr(error, 'retryable', False) or warning)
            self.retry_loading.setVisible(bool(error or warning))
            preserved = bool(error and retryable and getattr(self, 'listed_location', None) == self.location())
            same_location = getattr(self, 'listed_location', None) == self.location()
            selected = {(str(entry.path), entry.member) for entry in self.selected()} if same_location else set()
            current = self.entry_at(self.table.currentIndex()) if same_location else None
            current_key = (str(current.path), current.member) if current else None
            if not preserved:
                self.model.replace(entries or [])
            if not error:
                self.listed_location = (directory, archive, prefix)
                for row, entry in enumerate(self.model.entries):
                    key = (str(entry.path), entry.member)
                    if key not in selected and key != current_key:
                        continue
                    index = self.proxy.mapFromSource(self.model.index(row, 0))
                    if not index.isValid():
                        continue
                    if key in selected:
                        self.table.selectionModel().select(index, QItemSelectionModel.Select | QItemSelectionModel.Rows)
                    if key == current_key:
                        self.table.selectionModel().setCurrentIndex(index, QItemSelectionModel.NoUpdate)
                name = getattr(self, 'return_selection', None)
                if name:
                    for row, entry in enumerate(self.model.entries):
                        if entry.name == name:
                            index = self.proxy.mapFromSource(self.model.index(row, 0))
                            if index.isValid():
                                self.table.selectRow(index.row())
                                self.table.setCurrentIndex(index)
                                self.table.scrollTo(index)
                            break
                    self.return_selection = None
            message = str(error) if error else warning or (self.main.tr_key('empty') if not entries else '')
            if preserved and self.model.entries:
                message = 'Zuletzt geladene Dateiliste / Last loaded listing · ' + message
            self.message.setText(message)
            self.selection_changed()
            if profile and retryable and self.cloud_retry_count < 3 and not cancel.is_set():
                self.cloud_retry_count += 1
                delay = self.cloud_retry_count * 10
                self.message.setText(message + f' · Erneuter Versuch in {delay} s / Retrying')
                def retry():
                    if generation == self.generation and not cancel.is_set() and not self.main.closing:
                        self.refresh(automatic=True)
                QTimer.singleShot(delay * 1000, self, retry)
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.main.start_background(task)

    def entry_at(self, index):
        if not index.isValid():
            return None
        return self.model.entries[self.proxy.mapToSource(index).row()]

    def selected(self):
        return [self.entry_at(index) for index in self.table.selectionModel().selectedRows()]

    def selection_changed(self, *args):
        selected = self.selected()
        filtered = bool(self.filter.text())
        de = self.main.language == 'de'
        total, shown = self.model.rowCount(), self.proxy.rowCount()
        self.filter_hint.setVisible(filtered)
        self.clear_filter.setVisible(filtered)
        self.filter_hint.setText((f'{shown} von {total} Einträgen · Filter aktiv' if de else
                                  f'{shown} of {total} entries · Filter active') if shown else
                                 ('Keine Treffer für diesen Filter.' if de else 'No matches for this filter.'))
        self.selected_label.setText(f'{len(selected)} {self.main.tr_key("selected")}  ·  '
            f'{self.proxy.rowCount()} {self.main.tr_key("items")}')
        if self.main.active is self:
            self.main.update_context_actions()

    def open_entry(self, entry):
        if not entry:
            return
        self.main.activate(self)
        if entry.error:
            self.message.setText(entry.error)
            return
        if entry.member:
            if entry.directory:
                self.navigate(self.directory, self.archive, entry.member)
            else:
                self.main.open_entry(entry)
        elif entry.directory:
            self.navigate(entry.path)
        elif is_archive(entry.path):
            self.navigate(entry.path.parent, entry.path)
        else:
            self.main.open_entry(entry)

    def retranslate(self):
        self.filter.setPlaceholderText(self.main.tr_key('filter'))
        de = self.main.language == 'de'
        self.filter.setAccessibleName('Dateien im aktuellen Ordner filtern' if de else 'Filter files in this folder')
        self.filter.setToolTip('Filtert nur diese Liste. Strg+F sucht auch in Unterordnern. Esc löscht den Filter.' if de else
                               'Filters this list only. Ctrl+F also searches subfolders. Esc clears the filter.')
        self.clear_filter.setText('Filter löschen' if de else 'Clear filter')
        self.model.headerDataChanged.emit(Qt.Horizontal, 0, 3)
        self.selection_changed()


class MainWindow(QMainWindow):
    operation_finished = Signal(object)

    def __init__(self, state_dir, left=None, right=None):
        super().__init__()
        self.state_dir = Path(state_dir)
        self.engine = FileEngine(self.state_dir)
        self.settings = QSettings(str(self.state_dir / 'settings.ini'), QSettings.IniFormat)
        self.location_preferences = load_preferences(self.settings.value('locations', '[]'))
        self.place_order = load_order(self.settings.value('place_order', '[]'))
        try:
            profiles = json.loads(self.settings.value('online_profiles', '[]'))
            self.online_profiles = [row for row in profiles if isinstance(row, dict) and isinstance(row.get('id'), str) and row['id'].startswith('oc_') and row['id'][3:].isalnum() and isinstance(row.get('name'), str)] if isinstance(profiles, list) else []
        except (TypeError, ValueError):
            self.online_profiles = []
        self.external_cloud_profiles = []
        locale = os.environ.get('LANG', 'en')
        self.language = str(self.settings.value('language', 'de' if locale.startswith('de') else 'en'))
        self.dark = self.settings.value('dark', True, type=bool)
        self.hidden = self.settings.value('hidden', False, type=bool)
        self.busy = False
        self.operation_running = False
        self.operation_queue = []
        self.active_transfer_id = None
        self.transfers_paused = False
        self.cancel_requested = False
        self.closing = False
        self.active = None
        self.panes = []
        self.tasks = set()
        self.pool = QThreadPool(self)
        self.pool.setMaxThreadCount(4)
        self.operation_pool = QThreadPool(self)
        self.operation_pool.setMaxThreadCount(1)
        self.thumbnails = ThumbnailCache(self)
        self.setWindowTitle(f'OpenCommander · Linux {__version__}')
        self.resize(1440, 880)
        self.setMinimumSize(1000, 580)
        icon = Path(__file__).resolve().parent / 'assets' / 'opencommander.png'
        self.setWindowIcon(QIcon(str(icon)))
        central = QWidget()
        layout = QVBoxLayout(central)
        layout.setContentsMargins(16, 12, 16, 10)
        layout.setSpacing(10)
        self.setCentralWidget(central)
        header = QHBoxLayout()
        brand = QLabel('OpenCommander')
        brand.setObjectName('brand')
        header.addWidget(brand)
        label = QLabel('LINUX ' + __version__)
        label.setObjectName('badge')
        header.addWidget(label)
        header.addStretch()
        self.mode_label = QLabel()
        header.addWidget(self.mode_label)
        self.mode = ModeToggle()
        header.addWidget(self.mode)
        self.theme_button = QCheckBox()
        self.theme_button.setChecked(self.dark)
        self.theme_button.clicked.connect(self.toggle_theme)
        self.theme_button.setObjectName("darkModeCheckbox")
        header.addWidget(self.theme_button)
        self.location_settings_button = QPushButton()
        self.location_settings_button.clicked.connect(self.location_settings)
        header.addWidget(self.location_settings_button)
        settings_action = QAction(self)
        settings_action.setShortcut(QKeySequence('Ctrl+,'))
        settings_action.triggered.connect(self.location_settings)
        self.addAction(settings_action)
        layout.addLayout(header)
        self.actions = {}
        callbacks = {
            'copy': (lambda: self.transfer(False), 'F5'), 'move': (lambda: self.transfer(True), 'F6'),
            'rename': (self.rename_selected, 'F2'), 'trash': (self.trash_selected, 'Delete'),
            'zip': (self.zip_selected, ''), 'extract': (self.extract_selected, ''),
            'undo': (self.undo, 'Ctrl+Z'), 'new_folder': (self.new_folder, 'Ctrl+Shift+N'),
            'open_with': (self.open_with_selected, ''),
            'open': (self.open_selected, 'Ctrl+O'), 'preview': (self.preview_selected, 'Ctrl+Y'),
            'refresh': (self.refresh_all, 'Ctrl+R'), 'hidden': (self.toggle_hidden, 'Ctrl+H'),
            'folder': (self.choose_folder, 'Ctrl+Shift+O'), 'history': (self.toggle_history, ''),
            'search': (lambda: self.show_tools('search'), 'Ctrl+F'),
            'compare': (lambda: self.show_tools('compare'), 'Ctrl+Alt+C'),
            'multi_rename': (lambda: self.show_tools('rename'), 'Ctrl+Shift+M'),
            'help': (self.help, 'F1'), 'info': (self.info, 'Ctrl+I'),
        }
        self.toolbar = QToolBar()
        self.toolbar.setToolButtonStyle(Qt.ToolButtonTextOnly)
        for key, (callback, shortcut) in callbacks.items():
            action = QAction(self)
            if shortcut:
                action.setShortcut(QKeySequence(shortcut))
            action.triggered.connect(callback)
            self.actions[key] = action
            self.addAction(action)
        self.actions['hidden'].setCheckable(True)
        self.actions['hidden'].setChecked(self.hidden)
        for key in ('search', 'rename', 'new_folder', 'trash', 'zip', 'extract', 'preview', 'undo', 'history', 'help'):
            self.toolbar.addAction(self.actions[key])
            self.toolbar.widgetForAction(self.actions[key]).setProperty('actionKind', key)
        tools_button = QPushButton('Werkzeuge' if self.language == 'de' else 'Tools')
        tools_menu = QMenu(tools_button)
        tools_menu.addAction(self.actions['compare'])
        tools_menu.addAction(self.actions['multi_rename'])
        tools_button.setMenu(tools_menu)
        self.toolbar.addWidget(tools_button)
        self.tools_button = tools_button
        self.hidden_checkbox = QCheckBox()
        self.hidden_checkbox.setChecked(self.hidden)
        self.hidden_checkbox.clicked.connect(self.toggle_hidden)
        self.toolbar.addWidget(self.hidden_checkbox)
        layout.addWidget(self.toolbar)
        self.places = QHBoxLayout()
        places_widget = QWidget()
        places_widget.setObjectName('places')
        places_widget.setLayout(self.places)
        places_scroll = QScrollArea()
        places_scroll.setWidgetResizable(True)
        places_scroll.setWidget(places_widget)
        places_scroll.setFixedHeight(68)
        layout.addWidget(places_scroll)
        self.integration_locations = []
        self.integration_scanning = False
        self.integration_timer = QTimer(self)
        self.integration_timer.timeout.connect(self.scan_integrations)
        self.integration_timer.start(5000)
        QTimer.singleShot(0, self.scan_integrations)
        split = QSplitter(Qt.Horizontal)
        downloads = Path(QStandardPaths.writableLocation(QStandardPaths.DownloadLocation))
        defaults = [left or self.settings.value('pane1', '/'), right or self.settings.value('pane2', str(downloads or Path.home()))]
        for index, path in enumerate(defaults, 1):
            pane = Pane(self, index, Path(path))
            self.panes.append(pane)
            split.addWidget(pane)
        split.setSizes([700, 700])
        layout.addWidget(split, 1)
        self.status = QLabel()
        self.status.setObjectName('muted')
        self.status.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.transfer_details = QLabel()
        self.transfer_details.setObjectName('transferDetails')
        self.transfer_details.setWordWrap(True)
        self.transfer_details.setTextFormat(Qt.PlainText)
        self.transfer_details.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.transfer_details.hide()
        layout.addWidget(self.transfer_details)
        self.progress = QProgressBar()
        self.progress.setFixedWidth(160)
        self.progress.hide()
        self.cancel_button = QPushButton()
        self.cancel_button.clicked.connect(self.cancel_operations)
        self.cancel_button.hide()
        footer = QHBoxLayout()
        footer.addWidget(self.status, 1)
        self.queue_label = QLabel()
        self.queue_label.setObjectName("operationQueue")
        footer.addWidget(self.queue_label)
        self.pause_button = QPushButton()
        self.pause_button.clicked.connect(self.pause_transfers)
        self.pause_button.hide()
        footer.addWidget(self.pause_button)
        self.resume_button = QPushButton()
        self.resume_button.clicked.connect(self.resume_saved_transfers)
        self.resume_button.hide()
        footer.addWidget(self.resume_button)
        footer.addWidget(self.progress)
        footer.addWidget(self.cancel_button)
        layout.addLayout(footer)
        from .transfers_ui import TransferOverview
        self.transfers = TransferOverview(self)
        layout.insertWidget(layout.count()-2, self.transfers)
        self.history_dock = QDockWidget(self)
        self.history_list = QListWidget()
        self.history_cards = {}
        self.history_operations = {}
        self.history_list.viewport().installEventFilter(self)
        self.history_list.setHorizontalScrollMode(QAbstractItemView.ScrollPerPixel)
        self.history_list.setSpacing(8)
        self.history_list.setFlow(QListWidget.LeftToRight)
        self.history_list.setWrapping(False)
        self.history_list.horizontalScrollBar().valueChanged.connect(self.load_history_previews)
        self.history_dock.setMinimumWidth(380)
        self.history_dock.setMinimumHeight(345)
        self.history_list.verticalScrollBar().valueChanged.connect(self.load_history_previews)
        self.history_dock.visibilityChanged.connect(self.history_visibility_changed)
        self.history_dock.setWidget(self.history_list)
        self.addDockWidget(Qt.BottomDockWidgetArea, self.history_dock)
        self.history_dock.hide()
        # Clipboard shortcuts belong to file lists. Text edits retain their normal shortcuts.
        for pane in self.panes:
            for sequence, callback in [('Ctrl+C', lambda: self.copy_clipboard(False)),
                ('Ctrl+X', lambda: self.copy_clipboard(True)), ('Ctrl+V', self.paste_clipboard),
                ('Ctrl+A', pane.table.selectAll)]:
                action = QAction(pane.table)
                action.setShortcut(QKeySequence(sequence))
                action.setShortcutContext(Qt.WidgetShortcut)
                action.triggered.connect(callback)
                pane.table.addAction(action)
        for sequence, callback in [('Ctrl+L', self.focus_path), ('Alt+Up', lambda: self.active.up()),
             ('Alt+Left', lambda: self.active.travel(-1)), ('Alt+Right', lambda: self.active.travel(1))]:
            action = QAction(self)
            action.setShortcut(QKeySequence(sequence))
            action.triggered.connect(callback)
            self.addAction(action)
        self.retranslate()
        self.apply_theme()
        self.activate(self.panes[0])
        self.status.setText(self.tr_key('ready'))
        saved_geometry = self.settings.value('geometry')
        if saved_geometry is not None:
            self.restoreGeometry(saved_geometry)
        self.reload_history()
        self.history_dock.setVisible(self.settings.value('history_visible', False, type=bool))
        if self.engine.load_error:
            self.status.setText(self.engine.load_error)
        if self.engine.transfers.error:
            self.status.setText(self.engine.transfers.error)
        else:
            QTimer.singleShot(0, lambda: self.resume_saved_transfers(automatic=True))

    def tr_key(self, key):
        return text(self.language, key)

    def activate(self, pane):
        self.active = pane
        for p in self.panes:
            accent = ('#6caaff' if p.number == 1 else '#60c69d') if self.dark else ('#1e66c1' if p.number == 1 else '#1f8a5b')
            active = '  •  ' + self.tr_key('active') if p == pane else ''
            from .external_cloud import root_for
            profile = next((row for row in self.online_profiles + self.external_cloud_profiles if p.directory == root_for(self, row) or
                            root_for(self, row) in p.directory.parents), None)
            device = next((row for row in self.integration_locations if row.get('path') and
                           (p.directory == Path(row['path']) or Path(row['path']) in p.directory.parents)), None)
            name = profile['name'] if profile else device['name'] if device else ''
            place = '  ·  ' + name if name else ''
            p.title.setText(self.tr_key('left' if p.number == 1 else 'right') + place + active)
            p.title.setStyleSheet(f'color: {accent}; font-weight: 700; letter-spacing: 1px;')
        self.update_context_actions()

    def update_context_actions(self):
        if not self.active or not hasattr(self.active, 'table'):
            return
        selected = self.active.selected()
        archive = bool(self.active.archive) or (len(selected) == 1 and not selected[0].directory
                   and is_archive(selected[0].path))
        self.actions['extract'].setVisible(archive)
        self.actions['extract'].setEnabled(archive and not self.closing)

    def start_background(self, task):
        self.tasks.add(task)
        task.signals.result.connect(lambda *_: self.tasks.discard(task))
        self.pool.start(task)

    def cancel_operations(self):
        if not self.closing:
            self.transfers.cancel_all()

    def pause_transfers(self):
        if not self.closing:
            self.transfers.pause_all()

    def run_copy_job(self, identifier, engine=None):
        engine = engine or self.engine
        job = engine.transfers.get(identifier)
        if job is None:
            return
        try:
            engine.check_cancel()
            from .online_ui import mount_profile, mount_path
            from .transfer_store import mount_identity
            for required in job['profiles']:
                profile = next((dict(row) for row in self.online_profiles if row['id'] == required['id']), None)
                if profile is None or profile['kind'] != required['kind'] or profile.get('remote_directory', '') != required['remote_directory']:
                    raise SafetyError('Gespeicherte Online-Verbindung wurde geändert / Saved connection changed')
                root = mount_path(self.state_dir, profile['id'])
                if str(root) != required['root']:
                    raise SafetyError('Online-Mountpfad geändert / Cloud mount path changed')
                mount_profile(self, profile, engine.cancel)
                for guard in job['guards']:
                    if guard.get('profile') == profile['id'] and guard['mount'] is None:
                        identity = mount_identity(guard['path'])
                        if identity is None or identity['root'] != str(root) or identity['filesystem'] != 'fuse.rclone':
                            raise SafetyError('Online-Laufwerk fehlt / Cloud mount missing')
                        guard['mount'] = identity
            engine.transfers.save(job)
        except Exception as error:
            if engine.cancel.is_set():
                if engine.pause.is_set():
                    job.update(status='paused', error=None)
                    engine.transfers.save(job)
                else:
                    from .resumable_copy import discard
                    discard(engine, identifier)
                raise Cancelled('Cancelled') from error
            job.update(status='blocked', error=str(error))
            engine.transfers.save(job)
            raise
        return engine.transfer(tuple(Path(p) for p in job['sources']), Path(job['directory']), job.get('move', False), job['conflict'], identifier)

    def resume_saved_transfers(self, automatic=False):
        self.transfers.restore(automatic)

    def update_queue_label(self):
        self.transfers.render()

    def run_readonly(self, callback, after):
        task = Task(callback)
        def done(value, error):
            if error:
                self.status.setText(str(error))
            elif not self.closing:
                after(value)
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.start_background(task)

    def run_operation(self, callback, after=None, transfer_id=None):
        if self.closing:
            return
        if transfer_id:
            self.transfers.submit(transfer_id, after)
            return
        reserved_action = hasattr(callback, 'reserved')
        allowed = self.transfers.can_run_file_action(callback) if reserved_action else not self.busy
        if (self.busy and not self.operation_running) or not allowed:
            if self.operation_running or (reserved_action and not self.busy):
                self.operation_queue.append((callback, after, None))
                self.update_queue_label()
                self.status.setText(getattr(callback, 'label', 'Dateivorgang / File operation') + ' · Wartet auf laufenden Vorgang / Waiting for current operation')
            return
        engine = getattr(callback, 'engine', self.engine)
        self.transfers.generic_engine = engine
        self.busy = self.operation_running = True
        self.transfers.generic_running = True
        for card in self.history_cards.values():
            if card:
                card.undo_button.setEnabled(False)
        engine.cancel.clear()
        engine.pause.clear()
        self.status.setText(self.tr_key('working'))
        self.progress.setRange(0, 0)
        self.progress.show()
        self.cancel_button.show()
        self.actions['undo'].setEnabled(False)
        self.update_queue_label()
        task = Task(callback)
        started = time.monotonic()
        latest = [None]
        timer = QTimer(self)
        timer.setInterval(250)
        def show_metrics():
            value = latest[0]
            if value is None:
                return
            elapsed = time.monotonic() - started
            total, count = value['bytes_total'], value['bytes_done']
            phase = value['phase']
            percent = 100 if phase == 'complete' else min(99, int(count * 100 / total)) if total else min(99, int(value['files_done'] * 100 / value['files_total'])) if value['files_total'] else 0
            phases = {'planning': ('Dateien und Größe ermitteln', 'Counting files and size'),
                      'copying': ('Kopieren', 'Copying'), 'moving': ('Verschieben', 'Moving'),
                      'uploading': ('Schreiben abschließen / Upload', 'Finishing writes / upload'),
                      'verifying': ('Prüfen und abschließen', 'Verifying and finalizing'),
                      'resuming': ('Gespeicherten Stand prüfen · kein erneutes Kopieren', 'Checking saved progress · not copying again'),
                      'checking_partial': ('Angefangene Datei prüfen', 'Checking partial file'),
                      'cleanup': ('Quelle bereinigen', 'Cleaning up source'),
                      'paused': ('Pausiert – gespeichert', 'Paused – saved'),
                      'cancelled': ('Abgebrochen', 'Cancelled'), 'complete': ('Abgeschlossen', 'Completed')}
            label = phases[phase][0 if self.language == 'de' else 1]
            clock = human_duration(elapsed, self.language)
            if phase == 'planning':
                self.progress.setRange(0, 0)
                details = f'{label} · {clock} · {value["name"]}'
            else:
                self.progress.setRange(0, 100)
                self.progress.setValue(percent)
                rate = max(0, count - value.get('bytes_resumed', 0)) / max(elapsed, 0.001)
                remaining = (total - count) / rate if rate and total > count else None
                eta = (' · Rest ca. ' if self.language == 'de' else ' · Remaining ~') + human_duration(remaining, self.language) if remaining is not None else ''
                files = 'Dateien' if self.language == 'de' else 'files'
                duration = 'Zeit' if self.language == 'de' else 'Time'
                details = (f'{label} · {percent}% · {human_size(count)} / {human_size(total)} · '
                           f'{value["files_done"]} / {value["files_total"]} {files} · {duration} {clock} · {human_size(rate)}/s{eta}\n'
                           f'{value["name"]}')
            self.transfer_details.setText(details)
            self.transfer_details.show()
        def report_metrics(value):
            latest[0] = value  # Coalesce immutable snapshots without queued GUI signals.
        self.transfer_details.hide()
        engine.metrics_report = report_metrics
        timer.timeout.connect(show_metrics)
        timer.start()
        last_progress = [0.0]
        def progress(count, name):
            now = time.monotonic()
            if now - last_progress[0] >= 0.1:
                last_progress[0] = now
                task.signals.progress.emit(count // 1024, name)
        engine.progress = progress
        def show_progress(kib, name):
            if not engine.cancel.is_set():
                self.status.setText(f'{self.tr_key("working")}  {human_size(kib * 1024)}  ·  {name}')
        task.signals.progress.connect(show_progress, Qt.QueuedConnection)
        def done(value, error):
            self.busy = False
            self.operation_running = False
            self.active_transfer_id = None
            self.transfers.generic_running = False
            self.transfers.sync_busy()
            timer.stop()
            timer.deleteLater()
            engine.metrics_report = lambda _: None
            if latest[0] is not None:
                if isinstance(error, Cancelled):
                    latest[0]['phase'] = 'paused' if engine.pause.is_set() else 'cancelled'
                show_metrics()
                if error and not isinstance(error, Cancelled):
                    self.transfer_details.setText(self.transfer_details.text() + '\n' + str(error))
                elif isinstance(value, dict) and value.get('warnings'):
                    self.transfer_details.setText(self.transfer_details.text() + '\n' + '\n'.join(value['warnings']))
            engine.progress = lambda *_: None
            self.progress.hide()
            self.cancel_button.hide()
            for action in self.actions.values():
                action.setEnabled(True)
            self.update_context_actions()
            if not self.closing:
                self.reload_history()
                if hasattr(self, 'cloud_listings'):
                    self.cloud_listings.invalidate()
                self.refresh_all()
            self.status.setText(('Pausiert – Zwischenstand gespeichert / Paused – progress saved' if engine.pause.is_set() else
                                 'Abgebrochen / Cancelled') if isinstance(error, Cancelled) else str(error) if error else self.tr_key('done'))
            if not error and after and not self.closing:
                after(value)
            if getattr(callback, 'finished', None):
                callback.finished(value, error)
            self.operation_finished.emit(error)
            self.transfers.pump()
            self.update_queue_label()
            if not self.busy and not self.operation_queue:
                self.cancel_requested = False
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.tasks.add(task)
        task.signals.result.connect(lambda *_: self.tasks.discard(task), Qt.QueuedConnection)
        self.operation_pool.start(task)

    def conflict_mode(self, paths, directory):
        if remote_location(directory) or any(remote_location(p) for p in paths):
            return 'keep'  # Resolve collisions in the worker, never stat a provider on the GUI thread.
        if not any(exists(Path(directory) / Path(p).name) and Path(p) != Path(directory) / Path(p).name for p in paths):
            return 'keep'
        dialog = QMessageBox(self)
        dialog.setWindowTitle(self.tr_key('copy'))
        dialog.setText(self.tr_key('conflict'))
        keep = dialog.addButton(self.tr_key('keep'), QMessageBox.AcceptRole)
        replace = dialog.addButton(self.tr_key('replace'), QMessageBox.DestructiveRole)
        dialog.addButton(self.tr_key('cancel'), QMessageBox.RejectRole)
        dialog.exec()
        return 'keep' if dialog.clickedButton() == keep else 'replace' if dialog.clickedButton() == replace else None

    def transfer(self, move=False, paths=None, directory=None, after=None):
        if self.closing or (self.busy and not self.operation_running):
            return
        pane = self.active
        target_pane = self.panes[1] if pane == self.panes[0] else self.panes[0]
        if directory is None and target_pane.archive:
            self.status.setText(self.tr_key('zip_readonly'))
            return
        directory = Path(directory or target_pane.directory)
        if paths is None and pane.archive:
            if move:
                self.status.setText(self.tr_key('zip_readonly'))
                return
            self.extract_selected(directory)
            return
        paths = paths if paths is not None else [entry.path for entry in pane.selected()]
        if not paths:
            self.status.setText(self.tr_key('no_selection'))
            return
        paths = tuple(Path(path) for path in paths)
        mode = self.conflict_mode(paths, directory)
        if mode:
            from .transfer_store import guards_for
            from .online_ui import mount_path
            endpoints = paths + (directory,)
            guards = guards_for(endpoints)
            profiles = []
            for profile in self.online_profiles:
                root = mount_path(self.state_dir, profile['id'])
                matching = [guard for guard in guards if Path(guard['path']) == root or root in Path(guard['path']).parents]
                if matching:
                    profiles.append(dict(id=profile['id'], kind=profile['kind'], root=str(root), remote_directory=profile.get('remote_directory', '')))
                    for guard in matching:
                        guard['profile'] = profile['id']
                        if not remote_location(root):
                            guard['mount'] = None
            try:
                job = self.engine.transfers.create(paths, directory, mode, guards, profiles, move=move)
            except Exception as error:
                self.status.setText(str(error))
                return
            self.run_operation(None, after, transfer_id=job['id'])

    def drop_urls(self, urls, directory):
        paths = [Path(url.toLocalFile()) for url in urls if url.isLocalFile()]
        if len(paths) != len(urls):
            self.status.setText('Only local file URLs are supported.')
            return
        self.transfer(self.mode.currentData() == 'move', paths, directory)

    def copy_clipboard(self, move):
        if self.closing or (self.busy and not self.operation_running) or self.active.archive:
            return
        paths = [entry.path for entry in self.active.selected()]
        if not paths:
            return
        mime = QMimeData()
        urls = [QUrl.fromLocalFile(str(path)) for path in paths]
        mime.setUrls(urls)
        mime.setData('x-special/gnome-copied-files',
                     (('cut' if move else 'copy') + '\n' + '\n'.join(url.toString(QUrl.FullyEncoded) for url in urls)).encode())
        mime.setData('application/x-kde-cutselection', b'1' if move else b'0')
        QApplication.clipboard().setMimeData(mime)
        self.status.setText(self.tr_key('cut' if move else 'clipboard'))

    def paste_clipboard(self):
        if self.closing or (self.busy and not self.operation_running) or self.active.archive:
            return
        mime = QApplication.clipboard().mimeData()
        if mime is None:
            return
        gnome = bytes(mime.data('x-special/gnome-copied-files'))
        urls = mime.urls()
        if not urls and gnome:
            urls = [QUrl(line) for line in gnome.decode().splitlines()[1:]]
        if not urls or any(not url.isLocalFile() for url in urls):
            return
        move = gnome.startswith(b'cut\n') or bytes(mime.data('application/x-kde-cutselection')) == b'1'
        paths, directory = [Path(url.toLocalFile()) for url in urls], self.active.directory
        mode = self.conflict_mode(paths, directory)
        if mode:
            before = [u.toString() for u in urls]
            def finished(_):
                current = QApplication.clipboard().mimeData()
                if move and current and [u.toString() for u in current.urls()] == before:
                    QApplication.clipboard().clear()
            self.transfer(move, paths, directory, finished)

    def selected_one(self):
        selected = self.active.selected()
        if len(selected) != 1:
            self.status.setText(self.tr_key('no_selection'))
            return None
        return selected[0]

    def rename_selected(self):
        if self.closing or (self.busy and not self.operation_running) or self.active.archive:
            return
        entry = self.selected_one()
        if entry:
            name, accepted = QInputDialog.getText(self, self.tr_key('rename'), self.tr_key('name_prompt'), text=entry.name)
            if accepted and name != entry.name:
                self.run_operation(lambda: self.engine.rename(entry.path, name))

    def new_folder(self):
        if self.closing or (self.busy and not self.operation_running) or self.active.archive:
            return
        directory = self.active.directory
        name, accepted = QInputDialog.getText(self, self.tr_key('new_folder'), self.tr_key('name_prompt'))
        if accepted:
            self.run_operation(lambda: self.engine.mkdir(directory, name))

    def run_trash(self, paths, finished=None):
        from .transfers_ui import resources
        paths = [Path(path) for path in paths]
        if not paths:
            return
        engine = self.engine.fork()
        def action():
            return engine.trash(paths)
        action.engine = engine
        action.reserved = list(dict.fromkeys(pair for path in paths for pair in resources(
            dict(sources=[str(path)], directory=str(path.parent), move=True))))
        action.label = ('Entfernen' if self.language == 'de' else 'Remove') + f' · {len(paths)} ' + ('Elemente' if self.language == 'de' else 'items')
        action.finished = finished
        def removed(operation):
            # Only hide entries acknowledged by a completed recovery operation.
            removed_paths = {record['source'] for record in operation['records']}
            for pane in self.panes:
                entries = [entry for entry in pane.model.entries if str(entry.path) not in removed_paths]
                if len(entries) != len(pane.model.entries):
                    pane.model.replace(entries)
                    pane.selection_changed()
        self.run_operation(action, removed)

    def trash_selected(self):
        if self.closing or (self.busy and not self.operation_running) or self.active.archive:
            return
        paths = [entry.path for entry in self.active.selected()]
        if paths and QMessageBox.question(self, self.tr_key('trash'), self.tr_key('confirm_trash'),
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No) == QMessageBox.Yes:
            self.run_trash(paths)

    def zip_selected(self):
        if self.closing or (self.busy and not self.operation_running) or self.active.archive:
            return
        paths = [entry.path for entry in self.active.selected()]
        if not paths:
            return
        directory = self.active.directory
        name, accepted = QInputDialog.getText(self, self.tr_key('zip'), self.tr_key('zip_name'), text='Archive.zip')
        if accepted and name and Path(name).name == name and name not in ('.', '..'):
            self.run_operation(lambda: self.engine.make_zip(paths, unique_path(directory,
                name if name.lower().endswith('.zip') else name + '.zip')))

    def extract_selected(self, directory=None):
        if self.closing or (self.busy and not self.operation_running):
            return
        # QAction.triggered supplies a bool when connected directly.
        if isinstance(directory, bool):
            directory = None
        pane = self.active
        other = self.panes[1] if pane == self.panes[0] else self.panes[0]
        if directory is None and other.archive:
            self.status.setText(self.tr_key('zip_readonly'))
            return
        directory = Path(directory or other.directory)
        members = None
        archive = pane.archive
        if archive:
            selected = pane.selected()
            members = [entry.member for entry in selected] if selected else ([pane.prefix] if pane.prefix else None)
        else:
            entry = self.selected_one()
            if not entry or not is_archive(entry.path):
                return
            archive = entry.path
        self.run_operation(lambda: self.engine.extract_zip(archive, directory, members))

    def undo(self, operation_id=None):
        if self.busy:
            return
        if isinstance(operation_id, bool):
            operation_id = None
        if self.engine.history:
            self.run_operation(lambda: self.engine.undo(operation_id))
        else:
            self.status.setText(self.tr_key('no_history'))

    def history_visibility_changed(self, visible):
        if visible:
            if getattr(self, 'history_dirty', False):
                self.reload_history()
            else:
                self.load_history_previews()

    def reload_history(self):
        self.actions['undo'].setEnabled(bool(self.engine.history) and not self.busy)
        if not self.history_dock.isVisible():
            self.history_dirty = True
            return
        self.history_dirty = False
        position = self.history_list.horizontalScrollBar().value()
        self.history_list.clear()
        self.history_cards.clear()
        self.history_operations = {operation['id']: operation for operation in self.engine.history}
        for operation in reversed(self.engine.history):
            item = QListWidgetItem()
            item.setData(Qt.UserRole, operation['id'])
            item.setSizeHint(QSize(350, 220))
            self.history_list.addItem(item)
        self.actions['undo'].setEnabled(bool(self.engine.history) and not self.busy)
        self.history_list.horizontalScrollBar().setValue(position)
        QTimer.singleShot(0, self.load_history_previews)

    def eventFilter(self, watched, event):
        if hasattr(self, 'history_list') and watched is self.history_list.viewport() and event.type() in (QEvent.Resize, QEvent.Show):
            QTimer.singleShot(0, self.load_history_previews)
        return super().eventFilter(watched, event)

    def load_history_previews(self, *args):
        if not self.history_dock.isVisible():
            return
        from .history_ui import HistoryCard
        visible = self.history_list.viewport().rect()
        count = self.history_list.count()
        # Fixed-size horizontal cards: binary-search the first visible item.
        # Scroll cost depends on visible cards, rather than the full history.
        low, high = 0, count
        while low < high:
            middle = (low + high) // 2
            rect = self.history_list.visualItemRect(self.history_list.item(middle))
            if rect.right() < visible.left():
                low = middle + 1
            else:
                high = middle
        rows = set()
        for row in range(low, count):
            item = self.history_list.item(row)
            rect = self.history_list.visualItemRect(item)
            if rect.left() > visible.right():
                break
            if visible.intersects(rect):
                rows.add(row)
                if row not in self.history_cards:
                    operation = self.history_operations.get(item.data(Qt.UserRole))
                    if operation is None:
                        continue
                    card = HistoryCard(self, operation)
                    self.history_list.setItemWidget(item, card)
                    self.history_cards[row] = card
                self.history_cards[row].request_preview()
        for row in self.history_cards.keys() - rows:
            self.history_list.removeItemWidget(self.history_list.item(row))
            self.history_cards.pop(row)

    def toggle_history(self):
        self.history_dock.setVisible(not self.history_dock.isVisible())
        self.settings.setValue('history_visible', self.history_dock.isVisible())

    def choose_folder(self):
        path = QFileDialog.getExistingDirectory(self, self.tr_key('folder'), str(self.active.directory))
        if path:
            self.active.navigate(Path(path))

    def focus_path(self):
        self.active.path_edit.setFocus()
        self.active.path_edit.selectAll()

    def open_selected(self):
        entry = self.selected_one()
        if entry:
            self.active.open_entry(entry)

    def open_with_selected(self):
        entry = self.selected_one()
        if not entry or self.closing:
            return
        if entry.member and entry.directory:
            self.status.setText(self.tr_key('zip_readonly'))
            return
        from .integrations import invoke
        def choose():
            return invoke('open-with', str(self.materialize(entry)))
        def done(result):
            if not result['launched']:
                self.status.setText('Abgebrochen' if self.language == 'de' else 'Cancelled')
            elif entry.member:
                self.status.setText(self.tr_key('archive_copy'))
        self.run_readonly(choose, done)

    def materialize(self, entry):
        if not entry.member:
            return entry.path
        cache = self.state_dir / 'previews'
        cache.mkdir(exist_ok=True, mode=0o700)
        directory = Path(tempfile.mkdtemp(dir=cache))
        target = directory / entry.name
        try:
            with open_archive(entry.path) as archive:
                checked_members(archive)
                info = archive.getinfo(entry.member)
                if info.file_size > 128 * 1024**2:
                    raise SafetyError('ZIP preview limit: 128 MiB')
                with archive.open(info) as inp, target.open('xb') as out:
                    total = 0
                    for block in iter(lambda: inp.read(1024 * 1024), b''):
                        total += len(block)
                        if total > min(info.file_size, 128 * 1024**2):
                            raise SafetyError('Archive preview size limit exceeded')
                        out.write(block)
                    if total != info.file_size:
                        raise SafetyError('Archive size mismatch')
            return target
        except Exception:
            shutil.rmtree(directory, ignore_errors=True)
            raise

    def open_entry(self, entry):
        if self.closing:
            return
        if media_kind(entry.name):
            self.open_media(entry)
            return
        def opened(path):
            if not QDesktopServices.openUrl(QUrl.fromLocalFile(str(path))):
                self.status.setText(self.tr_key('error') + ': ' + str(path))
            elif entry.member:
                self.status.setText(self.tr_key('archive_copy'))
        self.run_readonly(lambda: self.materialize(entry), opened)

    def open_media(self, entry):
        pane = self.active
        entries = [pane.entry_at(pane.proxy.index(row, 0)) for row in range(pane.proxy.rowCount())]
        entries = [item for item in entries if not item.directory and media_kind(item.name)]
        if entry not in entries:
            entries = [entry]
        if getattr(self, 'preview_dialog', None) is not None and isValid(self.preview_dialog):
            self.preview_dialog.close()
        self.preview_dialog = MediaViewer(self, entries, entries.index(entry))
        self.preview_dialog.show()

    @staticmethod
    def is_image(path):
        formats = {bytes(value).decode('ascii').lower() for value in QImageReader.supportedImageFormats()}
        return Path(path).suffix.lower().lstrip('.') in formats | {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tif', 'tiff', 'svg', 'heic', 'avif'}

    def preview_selected(self):
        entry = self.selected_one()
        if not entry or entry.directory or self.closing:
            return
        if media_kind(entry.name):
            self.open_media(entry)
        else:
            self.run_readonly(lambda: self.materialize(entry), lambda path: self.show_preview(path, entry))

    def show_preview(self, path, entry=None):
        dialog = QDialog(self)
        dialog.setAttribute(Qt.WA_DeleteOnClose)
        dialog.setWindowTitle(path.name)
        dialog.resize(850, 650)
        layout = QVBoxLayout(dialog)
        area = QTextEdit()
        area.setReadOnly(True)
        area.setPlainText(self.tr_key('loading'))
        layout.addWidget(area)
        task = Task(lambda: self.read_text_preview(path))
        def done(content, error):
            if isValid(area):
                area.setPlainText(str(error) if error else content)
        task.signals.result.connect(done)
        self.start_background(task)
        button = QPushButton(self.tr_key('open_external'))
        button.clicked.connect(lambda: QDesktopServices.openUrl(QUrl.fromLocalFile(str(path))))
        layout.addWidget(button)
        if entry and not entry.member:
            delete = QPushButton('In Papierkorb' if self.language == 'de' else 'Move to trash')
            def remove():
                if not self.closing and not (self.busy and not self.operation_running) and QMessageBox.question(dialog, self.tr_key('trash'),
                        self.tr_key('confirm_trash') + '\n' + str(entry.path),
                        QMessageBox.Yes | QMessageBox.No, QMessageBox.No) == QMessageBox.Yes:
                    self.run_trash([entry.path], lambda value, error: dialog.close() if not error and isValid(dialog) else None)
            delete.clicked.connect(remove)
            layout.addWidget(delete)
        self.preview_dialog = dialog
        dialog.show()

    def read_text_preview(self, path):
        try:
            with path.open('rb') as stream:
                content = stream.read(2 * 1024**2)
            return content.decode('utf-8') if b'\0' not in content else self.tr_key('preview_large')
        except (UnicodeError, OSError):
            return self.tr_key('open_external')

    def info(self):
        entry = self.selected_one()
        if entry:
            from .properties_ui import PropertiesDialog
            self.properties_dialog = PropertiesDialog(self, entry)
            self.properties_dialog.show()

    def help(self):
        from .help_ui import HelpDialog
        dialog = getattr(self, 'help_dialog', None)
        if dialog is None or not isValid(dialog):
            dialog = self.help_dialog = HelpDialog(self)
        dialog.retranslate()
        dialog.show()
        dialog.raise_()
        dialog.activateWindow()

    def refresh_all(self):
        for pane in self.panes:
            pane.refresh()

    def toggle_hidden(self):
        self.hidden = not self.hidden
        self.hidden_checkbox.setChecked(self.hidden)
        self.settings.setValue('hidden', self.hidden)
        self.actions['hidden'].setChecked(self.hidden)
        for pane in self.panes:
            pane.tree_model.setFilter(QDir.AllDirs | QDir.NoDotAndDotDot | (QDir.Hidden if self.hidden else QDir.Filter(0)))
        self.refresh_all()

    def change_language(self, language):
        self.language = language
        self.settings.setValue('language', self.language)
        self.retranslate()

    def retranslate(self):
        self.location_settings_button.setText('Einstellungen / Orte' if self.language == 'de' else 'Settings / Locations')
        self.tools_button.setText('Werkzeuge' if self.language == 'de' else 'Tools')
        for key, action in self.actions.items():
            action.setText(self.tr_key(key))
            action.setToolTip(self.tr_key(key) + (f' ({action.shortcut().toString()})' if not action.shortcut().isEmpty() else ''))
        for key, de, en in [('search', 'Suchen', 'Search'), ('compare', 'Ordner vergleichen', 'Compare folders'), ('multi_rename', 'Mehrfach umbenennen', 'Multi-rename')]:
            self.actions[key].setText(de if self.language == 'de' else en)
        self.actions['open_with'].setText('Öffnen mit …' if self.language == 'de' else 'Open with …')
        self.mode.set_labels(self.tr_key('copy'), self.tr_key('move'))
        self.hidden_checkbox.setText(self.tr_key('hidden'))
        self.mode_label.setText('Beim Ziehen:' if self.language == 'de' else 'When dragging:')
        self.mode.setToolTip('Gilt für Drag & Drop. F5 kopiert, F6 verschiebt unabhängig davon.' if self.language == 'de' else
                             'Used for drag and drop. F5 always copies and F6 always moves.')
        self.theme_button.setText(self.tr_key('dark'))
        self.theme_button.setChecked(self.dark)
        self.cancel_button.setText(self.tr_key('cancel'))
        self.pause_button.setText('Pause' if self.language == 'de' else 'Pause')
        self.resume_button.setText('Fortsetzen' if self.language == 'de' else 'Resume')
        self.update_queue_label()
        self.history_dock.setWindowTitle(self.tr_key('history'))
        for pane in self.panes:
            pane.retranslate()
        self.activate(self.active or self.panes[0])
        self.update_places()
        self.reload_history()

    def scan_integrations(self):
        if self.integration_scanning or self.closing:
            return
        from .integrations import invoke
        self.integration_scanning = True
        from .external_cloud import discover
        def scan():
            external = discover()
            try:
                locations = invoke()
            except Exception:
                locations = None  # A broken GVFS service must not hide rclone cloud actions.
            return locations, cloud_locations(), external
        task = Task(scan)
        self.tasks.add(task)
        def done(value, error):
            self.tasks.discard(task)
            self.integration_scanning = False
            if not error:
                locations, clouds, external = value
                if locations is None:
                    locations = self.integration_locations
                from .online_ui import mount_path
                saved_roots = {str(mount_path(self.state_dir, row['id'])) for row in self.online_profiles}
                external = [row for row in external if row['mount_root'] not in saved_roots]
                external_changed = external != self.external_cloud_profiles
                if external_changed or locations != self.integration_locations or clouds != getattr(self, 'local_cloud_places', []):
                    self.integration_locations = locations
                    self.local_cloud_places = clouds
                    self.external_cloud_profiles = external
                    self.update_places()
                    if external_changed:
                        for pane in self.panes:
                            if pane.remote and not pane.archive:
                                pane.refresh()
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.pool.start(task)

    def save_online_profiles(self):
        self.settings.setValue('online_profiles', json.dumps(self.online_profiles, ensure_ascii=False))
        self.settings.sync()
        self.update_places()

    def online_locations(self):
        if self.closing:
            return
        from .online_ui import OnlineDialog
        if not hasattr(self, 'online_dialog'):
            self.online_dialog = OnlineDialog(self)
        self.online_dialog.show()
        self.online_dialog.raise_()

    def show_tools(self, mode):
        if self.closing:
            return
        if any(pane.archive for pane in (self.panes if mode == 'compare' else [self.active])):
            self.status.setText('Werkzeuge unterstützen keine ZIP-Inhalte / Tools do not support ZIP contents')
            return
        from .tools_ui import ToolsDialog
        self.tools_dialog = ToolsDialog(self, mode)
        self.tools_dialog.show()

    def location_settings(self):
        if self.closing:
            return
        existing = getattr(self, 'location_settings_dialog', None)
        if existing is not None and isValid(existing) and existing.isVisible():
            existing.raise_()
            existing.activateWindow()
            return
        from .location_settings import LocationSettingsDialog
        self.location_settings_dialog = LocationSettingsDialog(self, getattr(self, 'known_locations', []))
        self.location_settings_dialog.show()
        self.location_settings_dialog.raise_()
        self.location_settings_dialog.activateWindow()

    def show_trash(self):
        from .trash_ui import TrashDialog
        if not hasattr(self, 'trash_dialog'):
            self.trash_dialog = TrashDialog(self)
        self.trash_dialog.refresh()
        self.trash_dialog.show()
        self.trash_dialog.raise_()

    def connections(self):
        from .connections_ui import ConnectionsDialog
        if not hasattr(self, 'connections_dialog'):
            self.connections_dialog = ConnectionsDialog(self)
        self.connections_dialog.timer.start(5000)
        self.connections_dialog.show()
        self.connections_dialog.raise_()
        self.connections_dialog.refresh()

    def update_places(self):
        if getattr(self, 'place_drag_active', False):
            self.places_update_pending = True
            return
        while self.places.count():
            item = self.places.takeAt(0)
            if item.widget():
                item.widget().hide()
                item.widget().deleteLater()
        locations = [(self.tr_key('root'), Path('/')), (self.tr_key('home'), Path.home())]
        downloads = Path(QStandardPaths.writableLocation(QStandardPaths.DownloadLocation))
        if downloads.is_absolute():
            locations.append((self.tr_key('downloads'), downloads))
        locations += [(item['name'], Path(item['path'])) for item in self.integration_locations if item['path']]
        locations += [(path.name, path) for path in mounted_locations() + getattr(self, 'local_cloud_places', [])]
        from .online_ui import mount_path
        from .provider_mounts import register
        online_mounts = [(row['name'], mount_path(self.state_dir, row['id'])) for row in self.online_profiles]
        for _, path in online_mounts:
            if remote_location(path):
                register(path)
        locations += online_mounts
        locations += [(row['name'], Path(row['mount_root'])) for row in self.external_cloud_profiles]
        trash = PlaceButton(self, 'Papierkorb' if self.language == 'de' else 'Trash', 'trash')
        trash.setIcon(self.style().standardIcon(QStyle.SP_TrashIcon))
        trash.clicked.connect(self.show_trash)
        rows = [dict(key='trash', button=trash)]
        self.known_locations = locations
        locations = [(name, Path(path)) for name, path in configured_locations(locations, self.location_preferences)]
        seen = set()
        for name, path in locations:
            if path in seen:
                continue
            seen.add(path)
            button = PlaceButton(self, name, self.place_key(path))
            button.setToolTip(str(path))
            button.setObjectName('place')
            profile = next((row for row in self.online_profiles if mount_path(self.state_dir, row['id']) == path), None)
            from .external_cloud import root_for
            icon_profile = profile or next((row for row in self.external_cloud_profiles if root_for(self, row) == path), None)
            if icon_profile:
                button.setIcon(provider_icon(icon_profile.get('kind')))
            else:
                device = next((row for row in self.integration_locations if row.get('path') == str(path)), None)
                standard = QStyle.SP_DriveHDIcon if device else QStyle.SP_DirHomeIcon if path == Path.home() else QStyle.SP_DirIcon
                button.setIcon(self.style().standardIcon(standard))
            if profile:
                button.clicked.connect(lambda checked=False, profile=profile: self.open_online_profile(profile))
            else:
                button.clicked.connect(lambda checked=False, path=path: self.active.navigate(path))
            button.edit_place = lambda profile=profile: self.edit_online_profile(profile) if profile else self.location_settings()
            rows.append(dict(key=button.place_key, button=button))
        for device in self.integration_locations:
            if device.get('mounted') or device.get('path'):
                continue
            button = PlaceButton(self, device['name'], 'device:' + device['id'])
            button.setIcon(self.style().standardIcon(QStyle.SP_DriveHDIcon))
            button.setObjectName('unmountedDevice')
            button.setToolTip('Datenträger einbinden und öffnen' if self.language == 'de' else 'Mount and open drive')
            button.clicked.connect(lambda checked=False, device=dict(device): self.open_device(device))
            button.setEnabled(device['id'] not in getattr(self, 'opening_devices', set()))
            rows.append(dict(key=button.place_key, button=button))
        self.place_buttons = [row['button'] for row in ordered_places(rows, self.place_order)]
        for button in self.place_buttons:
            hint = 'Zum Umsortieren ziehen; Rechtsklick für Optionen.' if self.language == 'de' else 'Drag to reorder; right-click for options.'
            button.setToolTip((button.toolTip() + '\n' + hint).strip())
            button.setContextMenuPolicy(Qt.CustomContextMenu)
            button.customContextMenuRequested.connect(lambda point, button=button: self.place_menu(button, point))
            self.places.addWidget(button)
        self.places.addStretch()
        if self.active and self.panes:
            self.activate(self.active)

    def place_key(self, path):
        from .online_ui import mount_path
        path = Path(path)
        profile = next((row for row in self.online_profiles if mount_path(self.state_dir, row['id']) == path), None)
        if profile:
            return 'online:' + profile['id']
        device = next((row for row in self.integration_locations if row.get('path') == str(path)), None)
        if device:
            return 'device:' + (device.get('volume_id') or device['id'])
        return 'path:' + str(path)

    def reorder_place(self, source, target, before=True):
        buttons = self.place_buttons
        moving = next((button for button in buttons if button.place_key == source), None)
        anchor = next((button for button in buttons if button.place_key == target), None)
        if moving is None or anchor is None or moving is anchor:
            return
        buttons.remove(moving)
        buttons.insert(buttons.index(anchor) + (0 if before else 1), moving)
        # Keep unavailable/hidden places in their saved slots, so reconnecting does
        # not reset their order. Newly discovered places join at the end.
        visible = [button.place_key for button in buttons]
        remaining = iter(visible)
        order = [next(remaining) if key in visible else key for key in self.place_order]
        order.extend(remaining)
        self.place_order = order
        self.settings.setValue('place_order', json.dumps(order))
        self.settings.sync()
        self.places.removeWidget(moving)
        self.places.insertWidget(buttons.index(moving), moving)

    def place_menu(self, button, point):
        menu = QMenu(button)
        index = self.place_buttons.index(button)
        for title, offset in [('Nach links' if self.language == 'de' else 'Move left', -1),
                              ('Nach rechts' if self.language == 'de' else 'Move right', 1)]:
            action = menu.addAction(title)
            action.setEnabled(0 <= index + offset < len(self.place_buttons))
            action.triggered.connect(lambda checked=False, offset=offset: self.reorder_place(
                button.place_key, self.place_buttons[index + offset].place_key, offset < 0))
        if hasattr(button, 'edit_place'):
            menu.addSeparator()
            menu.addAction('Bearbeiten …' if self.language == 'de' else 'Edit …', button.edit_place)
        menu.exec(button.mapToGlobal(point))

    def open_device(self, device):
        if self.closing:
            return
        if device.get('mounted') and device.get('path'):
            self.active.navigate(Path(device['path']))
            return
        from .integrations import invoke
        pending = getattr(self, 'opening_devices', set())
        self.opening_devices = pending
        if device['id'] in pending:
            return
        pending.add(device['id'])
        pane = self.active
        generation = pane.generation
        self.status.setText(('Datenträger einbinden: ' if self.language == 'de' else 'Mounting drive: ') + device['name'])
        self.update_places()
        task = Task(lambda: invoke('mount', device['id']))
        def done(locations, error):
            pending.discard(device['id'])
            if self.closing:
                return
            if error:
                self.status.setText(str(error))
            else:
                self.integration_locations = locations
                mounted = next((row for row in locations if row.get('mounted') and row.get('path') and
                                (row.get('volume_id') == device['id'] or row['id'] == device['id'])), None)
                if mounted:
                    if pane.generation == generation:
                        pane.navigate(Path(mounted['path']))
                    self.status.setText(('Datenträger bereit: ' if self.language == 'de' else 'Drive ready: ') + mounted['name'])
                else:
                    self.status.setText('Kein Dateipfad verfügbar. Datenträger erneut auswählen. / No file path available; select the drive again.')
            self.update_places()
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.start_background(task)

    def edit_online_profile(self, profile):
        if self.closing:
            return
        self.online_locations()
        dialog = self.online_dialog
        if dialog.pending:
            return
        index = next((i for i in range(dialog.saved.count()) if dialog.saved.itemData(i)['id'] == profile['id']), -1)
        if index >= 0:
            dialog.saved.setCurrentIndex(index)
            dialog.edit_saved()

    def open_online_profile(self, profile):
        if self.closing:
            return
        from .online_ui import mount_profile, mount_path
        if not hasattr(self, 'server_secrets'):
            self.server_secrets = {}
        path = mount_path(self.state_dir, profile['id'])
        if remote_location(path):
            self.active.navigate(path)
            return
        pending = getattr(self, 'opening_online', {})
        self.opening_online = pending
        if profile['id'] in pending:
            return
        if (profile.get('server_login') and profile.get('secret_required', profile.get('auth_mode') == 'password')
                and not profile.get('remember_secret') and profile['id'] not in self.server_secrets):
            secret, accepted = QInputDialog.getText(self, profile['name'],
                'Passwort / Passphrase' if self.language == 'de' else 'Password / Passphrase', QLineEdit.Password)
            if not accepted:
                return
            if not secret or any(c in secret for c in '\r\n\x00'):
                self.status.setText('Passwort/Passphrase erforderlich / Password or passphrase required')
                return
            self.server_secrets[profile['id']] = secret
        cancel = threading.Event()
        pending[profile['id']] = cancel
        pane = self.active
        generation = pane.generation
        self.status.setText(('Verbinden: ' if self.language == 'de' else 'Connecting: ') + profile['name'])
        task = Task(lambda: mount_profile(self, dict(profile), cancel))
        def done(path, error):
            pending.pop(profile['id'], None)
            if self.closing:
                return
            if error:
                self.status.setText(str(error) + ' · Rechtsklick auf Ort → Bearbeiten / Right-click location → Edit')
            else:
                if pane.generation == generation:
                    pane.navigate(path)
                self.status.setText(('Verbunden: ' if self.language == 'de' else 'Connected: ') + profile['name'])
                self.update_places()
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.start_background(task)

    def toggle_theme(self):
        self.dark = not self.dark
        self.settings.setValue('dark', self.dark)
        self.apply_theme()
        self.activate(self.active)
        self.theme_button.setText(self.tr_key('dark'))
        self.theme_button.setChecked(self.dark)
        dialog = getattr(self, 'location_settings_dialog', None)
        if dialog is not None and isValid(dialog):
            dialog.theme_checkbox.blockSignals(True)
            dialog.theme_checkbox.setChecked(self.dark)
            dialog.theme_checkbox.blockSignals(False)

    def apply_theme(self):
        bg, panel, inset, fg, muted, border, selection = (
            ('#171e2d', '#242e40', '#1c2638', '#e8eef9', '#afbed3', '#40516b', '#334f76') if self.dark else
            ('#eaf0fa', '#ffffff', '#f0f4fc', '#202c43', '#53647c', '#c9d6e8', '#dceaff'))
        blue, green, purple, gold, red = (
            ('#88baff', '#79dcb9', '#cfadff', '#f1c36d', '#ff919c') if self.dark else
            ('#185bb5', '#147454', '#753bb0', '#885400', '#b42338'))
        check_icon = (Path(__file__).parent / 'assets/check.svg').as_posix()
        self.setStyleSheet(f'''
            QMainWindow, QDialog, QWidget#places, QWidget#onlineBody, QScrollArea {{ background: {bg}; border: none; }}
            QWidget {{ color: {fg}; font-family: "DejaVu Sans"; font-size: 12px; }}
            QFrame#pane {{ background: {panel}; border: 1px solid {border}; border-radius: 10px; }}
            QFrame#pane[side="1"] {{ border-top: 3px solid {blue}; }}
            QFrame#pane[side="2"] {{ border-top: 3px solid {green}; }}
            QWidget#historyCard {{ background: {inset}; border: 1px solid {border}; border-radius: 8px; }}
            QWidget#transferOverview, QWidget#transferBody, QWidget#transferItems, QScrollArea#transferScroll {{ background: {bg}; border: none; }}
            QLabel {{ background: transparent; }}
            QLabel#transferTitle {{ font-weight: 600; }}
            QLabel#transferTitle[transferState="complete"] {{ color: {green}; }}
            QLabel#transferTitle[transferState="paused"], QLabel#transferTitle[transferState="pausing"] {{ color: {gold}; }}
            QLabel#transferTitle[transferState="blocked"] {{ color: {red}; }}
            QLabel#brand {{ color: {blue}; font-size: 25px; font-weight: 700; }}
            QLabel#badge {{ color: #6caaff; background: {inset}; padding: 5px 9px; border-radius: 4px; font-size: 10px; font-weight: 700; }}
            QLabel#muted {{ color: {muted}; font-size: 11px; }}
            QLineEdit, QComboBox, QSpinBox {{ background: {inset}; border: 1px solid {border}; padding: 7px; border-radius: 5px; selection-background-color: {selection}; }}
            QSpinBox QLineEdit {{ background: transparent; border: none; padding: 0; }}
            QPushButton, QToolButton {{ background: {panel}; border: 1px solid {border}; border-radius: 5px; padding: 7px 10px; }}
            QPushButton:hover, QToolButton:hover, QToolButton:checked {{ background: {selection}; }}
            QPushButton:disabled, QToolButton:disabled {{ color: {muted}; }}
            QToolButton[actionKind="copy"], QToolButton[actionKind="preview"] {{ color: {blue}; border-bottom: 2px solid {blue}; }}
            QToolButton[actionKind="move"], QToolButton[actionKind="new_folder"] {{ color: {green}; border-bottom: 2px solid {green}; }}
            QToolButton[actionKind="zip"], QToolButton[actionKind="extract"] {{ color: {purple}; border-bottom: 2px solid {purple}; }}
            QToolButton[actionKind="rename"], QToolButton[actionKind="undo"] {{ color: {gold}; border-bottom: 2px solid {gold}; }}
            QToolButton[actionKind="trash"] {{ color: {red}; border-bottom: 2px solid {red}; }}
            QToolButton[actionKind="new_folder"] {{ background: {'#173f2a' if self.dark else '#e9f8ef'}; color: {green}; }}
            QToolButton[actionKind="rename"], QToolButton[actionKind="preview"] {{ background: {'#1f344d' if self.dark else '#e8f1ff'}; color: {blue}; }}
            QToolButton[actionKind="trash"] {{ background: {'#51231f' if self.dark else '#ffe4e0'}; color: {red}; }}
            QToolButton[actionKind="zip"], QToolButton[actionKind="extract"] {{ background: {'#4b3514' if self.dark else '#fff4d8'}; color: {gold}; }}
            QToolButton:disabled {{ color: {muted}; border-bottom: 1px solid {border}; }}
            QPushButton#place {{ background: {inset}; color: {blue}; padding: 5px 10px; }}
            QCheckBox {{ spacing: 7px; padding: 4px; }}
            QCheckBox::indicator {{ width: 18px; height: 18px; border: 1px solid {border}; border-radius: 4px; background: {inset}; }}
            QCheckBox::indicator:checked {{ background: {green}; border: 2px solid {green}; image: url("{check_icon}"); }}
            QCheckBox#modeSwitch::indicator {{ width: 42px; height: 22px; border-radius: 11px; background: {blue}; }}
            QCheckBox#modeSwitch::indicator:checked {{ background: {green}; }}
            QToolBar {{ background: transparent; border: none; spacing: 6px; }}
            QTreeView, QTableView, QListWidget, QTextEdit {{ background: {panel}; alternate-background-color: {inset}; border: none; selection-background-color: {selection}; selection-color: {fg}; }}
            QTreeView::item {{ height: 29px; }}
            QHeaderView::section {{ background: {inset}; color: {muted}; border: none; padding: 8px 5px; font-size: 11px; }}
            QSplitter::handle {{ background: {bg}; width: 8px; }}
            QScrollBar:vertical {{ background: {inset}; width: 10px; }}
            QScrollBar::handle:vertical {{ background: {border}; min-height: 24px; border-radius: 4px; }}
            QProgressBar {{ background: {inset}; border: 1px solid {border}; border-radius: 4px; height: 8px; }}
            QProgressBar::chunk {{ background: #6caaff; }}
            QMenu, QComboBox QAbstractItemView {{ background: {panel}; color: {fg}; }}
            QMenu::item:selected {{ background: {selection}; }}
        ''')

    def closeEvent(self, event):
        if self.busy and self.cancel_requested:
            self.status.setText('Abbruch wird abgeschlossen … / Finishing cancellation …')
            QTimer.singleShot(100, self.close)
            event.ignore()
            return
        if self.busy and self.active_transfer_id:
            self.closing = True
            self.transfers_paused = True
            self.transfers.pause_all()
            self.status.setText('Kopierstand wird gespeichert … / Saving copy progress …')
            QTimer.singleShot(100, self.close)
            event.ignore()
            return
        if self.busy or getattr(self, 'opening_devices', set()) or (hasattr(self, 'connections_dialog') and self.connections_dialog.pending) or (hasattr(self, 'online_dialog') and self.online_dialog.pending):
            self.status.setText(self.tr_key('quit_busy'))
            event.ignore()
            return
        self.closing = True
        for cancel in getattr(self, 'opening_online', {}).values():
            cancel.set()
        self.integration_timer.stop()
        for pane in self.panes:
            pane.refresh_timer.stop()
            if pane.watcher.directories():
                pane.watcher.removePaths(pane.watcher.directories())
        if hasattr(self, 'connections_dialog'):
            self.connections_dialog.timer.stop()
        # Listing workers must finish before their signal receivers are destroyed.
        if getattr(self, 'preview_dialog', None) is not None and isValid(self.preview_dialog):
            self.preview_dialog.close()
        self.thumbnails.cancel_remote()
        for pane in self.panes:
            pane.load_cancel.set()
        if hasattr(self, 'tools_dialog'):
            self.tools_dialog.cancel.set()
        if self.tasks or self.pool.activeThreadCount() or self.operation_pool.activeThreadCount() or self.transfers.pool.activeThreadCount() or self.thumbnails.pool.activeThreadCount():
            self.status.setText('Hintergrundzugriffe werden beendet … / Finishing background requests …')
            QTimer.singleShot(100, self.close)
            event.ignore()
            return
        self.transfers.timer.stop()
        self.settings.setValue('geometry', self.saveGeometry())
        self.settings.sync()
        event.accept()
