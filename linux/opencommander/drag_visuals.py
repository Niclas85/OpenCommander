"""Small native cursor images complement the larger drag preview."""
from PySide6.QtCore import Qt, QPoint
from PySide6.QtGui import QPixmap, QPainter, QColor, QPen


def object_cursor(icon, mode, count=1, ratio=1.0):
    ratio = max(1.0, ratio)
    image = QPixmap(round(64 * ratio), round(64 * ratio))
    image.setDevicePixelRatio(ratio)
    image.fill(Qt.transparent)
    painter = QPainter(image)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setPen(QPen(QColor('#88baff'), 1))
    painter.setBrush(QColor('#242e40'))
    painter.drawRoundedRect(1, 1, 61, 61, 9, 9)
    painter.drawPixmap(8, 8, icon.pixmap(44, 44))
    color = {'copy': '#2563eb', 'move': '#b45309', 'blocked': '#b91c1c'}[mode]
    painter.setBrush(QColor(color))
    painter.setPen(QPen(QColor('#ffffff'), 2))
    painter.drawEllipse(QPoint(50, 50), 11, 11)
    if mode == 'copy':
        painter.drawLine(44, 50, 56, 50)
        painter.drawLine(50, 44, 50, 56)
    elif mode == 'move':
        painter.drawLine(43, 50, 56, 50)
        painter.drawLine(51, 45, 56, 50)
        painter.drawLine(51, 55, 56, 50)
    else:
        painter.drawLine(44, 56, 56, 44)
    if count > 1:
        painter.setBrush(QColor('#1e40af'))
        painter.setPen(Qt.NoPen)
        painter.drawRoundedRect(35, 1, 28, 20, 6, 6)
        painter.setPen(QColor('#ffffff'))
        font = painter.font()
        font.setBold(True)
        font.setPixelSize(10)
        painter.setFont(font)
        painter.drawText(35, 1, 28, 20, Qt.AlignCenter, str(count) if count < 100 else '99+')
    painter.end()
    return image
