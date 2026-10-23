"""Explicit publisher website entry point shared by Linux and Windows builds."""
from PySide6.QtCore import QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QMessageBox

MORE_APPS_URL = 'https://haenggi.vip/'


def more_apps_label(language):
    return 'Weitere Apps auf haenggi.vip ↗' if language == 'de' else 'More apps at haenggi.vip ↗'


def open_more_apps(parent, language):
    if QDesktopServices.openUrl(QUrl(MORE_APPS_URL)):
        return
    QMessageBox.warning(parent, 'haenggi.vip',
                        'Der Browser konnte nicht geöffnet werden: ' + MORE_APPS_URL if language == 'de' else
                        'Could not open the browser: ' + MORE_APPS_URL)
