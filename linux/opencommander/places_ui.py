"""Local shortcut presentation and ordering; dragging never transfers files."""
import json
from pathlib import Path

from PySide6.QtCore import Qt, QMimeData, QSize, QTimer
from PySide6.QtGui import QDrag, QIcon, QPainter, QColor, QPen
from PySide6.QtWidgets import QApplication, QPushButton


PLACE_MIME = 'application/x-opencommander-place'


def load_order(value):
    try:
        rows = json.loads(value)
    except (ValueError, TypeError):
        return []
    return list(dict.fromkeys(row for row in rows if isinstance(row, str))) if isinstance(rows, list) else []


def ordered_places(rows, order):
    rank = {key: index for index, key in enumerate(order)}
    return sorted(rows, key=lambda row: rank.get(row['key'], len(rank)))


def provider_icon(kind):
    # Bundled vector artwork works without a desktop icon theme or network access.
    kind = {'ftps': 'ftp'}.get(kind, kind)
    if kind not in {'onedrive', 'drive', 'dropbox', 'iclouddrive', 'ftp', 'sftp'}:
        return QIcon()
    path = Path(__file__).parent / 'assets' / 'providers' / (str(kind) + '.svg')
    return QIcon(str(path)) if path.is_file() else QIcon()


class PlaceButton(QPushButton):
    def __init__(self, main, title, key):
        super().__init__(title, main)
        self.main = main
        self.place_key = key
        self.press_position = None
        self.dragged = False
        self.drop_before = None
        self.setAcceptDrops(True)
        self.setIconSize(QSize(24, 24))

    def mousePressEvent(self, event):
        self.press_position = event.position().toPoint() if event.button() == Qt.LeftButton else None
        self.dragged = False
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if (event.buttons() & Qt.LeftButton and self.press_position is not None and
                (event.position().toPoint() - self.press_position).manhattanLength() >= QApplication.startDragDistance()):
            self.press_position = None
            self.dragged = True
            self.setDown(False)
            mime = QMimeData()
            mime.setData(PLACE_MIME, self.place_key.encode())
            drag = QDrag(self)
            drag.setMimeData(mime)
            drag.setPixmap(self.grab())
            drag.setHotSpot(event.position().toPoint())
            self.main.place_drag_active = True
            try:
                drag.exec(Qt.MoveAction)
            finally:
                self.main.place_drag_active = False
                if getattr(self.main, 'places_update_pending', False):
                    self.main.places_update_pending = False
                    QTimer.singleShot(0, self.main.update_places)
            return
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        self.press_position = None
        if self.dragged:
            self.setDown(False)
            event.accept()
            return
        super().mouseReleaseEvent(event)

    def accepts(self, event):
        source = event.source()
        return (isinstance(source, PlaceButton) and source.main is self.main and source is not self and
                event.mimeData().hasFormat(PLACE_MIME) and
                bytes(event.mimeData().data(PLACE_MIME)) == source.place_key.encode())

    def dragEnterEvent(self, event):
        self.dragMoveEvent(event)

    def dragMoveEvent(self, event):
        if self.accepts(event):
            self.drop_before = event.position().x() < self.width() / 2
            event.setDropAction(Qt.MoveAction)
            event.accept()
        else:
            self.drop_before = None
            event.ignore()
        self.update()

    def dragLeaveEvent(self, event):
        self.drop_before = None
        self.update()
        event.accept()

    def dropEvent(self, event):
        if self.accepts(event):
            self.main.reorder_place(event.source().place_key, self.place_key,
                                    event.position().x() < self.width() / 2)
            event.setDropAction(Qt.MoveAction)
            event.accept()
        else:
            event.ignore()
        self.drop_before = None
        self.update()

    def paintEvent(self, event):
        super().paintEvent(event)
        if self.drop_before is not None:
            painter = QPainter(self)
            painter.setPen(QPen(QColor('#4389ed'), 3))
            x = 2 if self.drop_before else self.width() - 3
            painter.drawLine(x, 4, x, self.height() - 4)
