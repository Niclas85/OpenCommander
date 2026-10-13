"""In-window file dragging: preview first, transfer only on mouse release."""
from pathlib import Path
from PySide6.QtCore import QObject, QEvent, Qt, QTimer, QPoint, QRect, QModelIndex
from PySide6.QtGui import QCursor
from PySide6.QtWidgets import QApplication, QLabel, QRubberBand
from .drag_visuals import object_cursor


class FileDrag(QObject):
    def __init__(self, table, entries, preview, icon):
        super().__init__(table)
        self.table, self.main = table, table.pane.main
        self.entries = tuple(entries)
        self.paths = tuple(entry.path for entry in entries)
        self.move_files = self.main.mode.currentData() == 'move'
        self.preview = preview
        self.target = None
        self.position = table.drag_position
        self.finished = False
        self.hover_tree = None
        self.hover_index = QModelIndex()
        self.root = self.main.centralWidget()
        self.ghost = QLabel(self.root)
        self.ghost.setObjectName('fileDragPreview')
        self.ghost.setAttribute(Qt.WA_TransparentForMouseEvents)
        self.ghost.setPixmap(preview)
        self.ghost.resize(preview.deviceIndependentSize().toSize())
        self.marker = QRubberBand(QRubberBand.Rectangle, self.root)
        self.marker.setAttribute(Qt.WA_TransparentForMouseEvents)
        self.cursor = QCursor(object_cursor(icon, 'move' if self.move_files else 'copy',
                                           len(entries), table.devicePixelRatioF()), 0, 0)
        self.blocked_cursor = QCursor(object_cursor(icon, 'blocked', len(entries), table.devicePixelRatioF()), 0, 0)
        QApplication.setOverrideCursor(self.cursor)
        QApplication.instance().installEventFilter(self)
        self.expand_timer = QTimer(self)
        self.expand_timer.setSingleShot(True)
        self.expand_timer.setInterval(650)
        self.expand_timer.timeout.connect(self.expand_hovered)
        self.scroll_timer = QTimer(self)
        self.scroll_timer.setInterval(60)
        self.scroll_timer.timeout.connect(self.scroll_hovered)
        self.scroll_timer.start()
        self.update_position(self.position)

    def target_at(self, position):
        if self.main.closing or (self.main.busy and not self.main.operation_running):
            return None
        for pane in self.main.panes:
            for view in (pane.tree, pane.table):
                viewport = view.viewport()
                point = viewport.mapFromGlobal(position)
                if not viewport.isVisible() or not viewport.rect().contains(point):
                    continue
                index = view.indexAt(point)
                if view is pane.tree:
                    if not index.isValid() or not pane.tree_model.isDir(index):
                        return None
                    directory = Path(pane.tree_model.filePath(index))
                    rect = view.visualRect(index).intersected(viewport.rect())
                else:
                    if pane.archive:
                        return None
                    entry = pane.entry_at(index)
                    directory = entry.path if entry and entry.directory else pane.directory
                    rect = view.visualRect(index) if entry and entry.directory else viewport.rect()
                # No remote stat/resolve on pointer movement. Entries/model are
                # already loaded; reject self/descendant/no-op targets lexically.
                if all(path.parent == directory for path in self.paths):
                    return None
                if any(entry.directory and (directory == entry.path or entry.path in directory.parents)
                       for entry in self.entries):
                    return None
                return pane, view, index, directory, rect
        return None

    def update_position(self, position):
        if self.finished:
            return
        self.position = position
        self.target = self.target_at(position)
        point = self.root.mapFromGlobal(position) + QPoint(14, 14)
        point.setX(max(0, min(point.x(), self.root.width() - self.ghost.width())))
        point.setY(max(0, min(point.y(), self.root.height() - self.ghost.height())))
        self.ghost.move(point)
        self.ghost.show()
        self.ghost.raise_()
        QApplication.changeOverrideCursor(self.cursor if self.target else self.blocked_cursor)
        if self.target:
            pane, view, index, directory, rect = self.target
            self.marker.setGeometry(QRect(view.viewport().mapTo(self.root, rect.topLeft()), rect.size()))
            self.marker.show()
            self.marker.raise_()
            if view is pane.tree and (view is not self.hover_tree or index != self.hover_index):
                self.hover_tree, self.hover_index = view, index
                self.expand_timer.start()
            elif view is not pane.tree:
                self.clear_hover()
        else:
            self.marker.hide()
            self.clear_hover()

    def clear_hover(self):
        self.expand_timer.stop()
        self.hover_tree, self.hover_index = None, QModelIndex()

    def expand_hovered(self):
        if not self.finished and self.hover_tree and self.hover_index.isValid():
            self.hover_tree.expand(self.hover_index)
            self.update_position(self.position)

    def scroll_hovered(self):
        if self.finished or not self.target:
            return
        view = self.target[1]
        y = view.viewport().mapFromGlobal(self.position).y()
        delta = -1 if y < 24 else 1 if y > view.viewport().height() - 24 else 0
        if delta:
            bar = view.verticalScrollBar()
            bar.setValue(bar.value() + delta * max(1, bar.singleStep()))
            self.update_position(self.position)

    def eventFilter(self, watched, event):
        if self.finished:
            return False
        kind = event.type()
        if kind == QEvent.KeyPress and event.key() == Qt.Key_Escape:
            self.cancel()
            return True
        if kind in (QEvent.Hide, QEvent.Close, QEvent.WindowDeactivate) and watched is self.main:
            self.cancel()
            return False
        if kind == QEvent.MouseMove:
            if not event.buttons() & Qt.LeftButton:
                self.cancel()  # Lost release/focus never means an implicit drop.
            elif not self.main.rect().contains(self.main.mapFromGlobal(event.globalPosition().toPoint())):
                self.export_native()
            else:
                self.update_position(event.globalPosition().toPoint())
            return True
        if kind == QEvent.MouseButtonRelease and event.button() == Qt.LeftButton:
            self.release(event.globalPosition().toPoint())
            return True
        return False

    def cleanup(self):
        if self.finished:
            return
        self.finished = True
        QApplication.instance().removeEventFilter(self)
        self.expand_timer.stop()
        self.scroll_timer.stop()
        self.ghost.hide()
        self.marker.hide()
        self.ghost.deleteLater()
        self.marker.deleteLater()
        QApplication.restoreOverrideCursor()
        self.table.file_drag = None
        self.table.setState(self.table.State.NoState)
        self.deleteLater()

    def cancel(self):
        self.cleanup()

    def release(self, position):
        target = self.target_at(position)
        self.cleanup()
        if target:
            pane, _, _, directory, _ = target
            self.main.activate(pane)
            self.main.transfer(self.move_files, self.paths, directory)

    def export_native(self):
        # Preserve the established local-URL offer to other applications.
        self.cleanup()
        self.table.export_drag(self.paths, self.preview, self.cursor.pixmap(), self.blocked_cursor.pixmap(), self.move_files)
