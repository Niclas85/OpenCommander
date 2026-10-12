"""Non-modal quick help and offline handbook entry points."""
from pathlib import Path
import sys

from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QPushButton, QLabel, QTextBrowser


def handbook_path():
    root = Path(sys.executable).parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parents[1]
    return root / 'docs' / 'handbuch' / 'index.html'


class HelpDialog(QDialog):
    def __init__(self, main):
        super().__init__(main)
        self.setAttribute(Qt.WA_DeleteOnClose)
        self.setWindowModality(Qt.NonModal)
        self.main = main
        self.resize(720, 560)
        layout = QVBoxLayout(self)
        self.intro = QLabel()
        self.intro.setWordWrap(True)
        layout.addWidget(self.intro)
        self.buttons = {}
        for anchor in ('anfang', 'tastatur', 'cloud', 'uebertragungen', 'probleme'):
            button = QPushButton()
            button.clicked.connect(lambda checked=False, anchor=anchor: self.open_chapter(anchor))
            self.buttons[anchor] = button
            layout.addWidget(button)
        self.shortcuts = QTextBrowser()
        self.shortcuts.setOpenExternalLinks(False)
        layout.addWidget(self.shortcuts, 1)
        self.notice = QLabel()
        self.notice.setWordWrap(True)
        self.notice.setTextFormat(Qt.PlainText)
        self.notice.setTextInteractionFlags(Qt.TextSelectableByMouse)
        layout.addWidget(self.notice)
        row = QHBoxLayout()
        row.addStretch()
        self.close_button = QPushButton()
        self.close_button.clicked.connect(self.close)
        row.addWidget(self.close_button)
        layout.addLayout(row)
        self.retranslate()

    def retranslate(self):
        de = self.main.language == 'de'
        self.setWindowTitle('Hilfe und Handbuch' if de else 'Help and handbook')
        self.intro.setText('Die Hilfe kann geöffnet bleiben, während du mit Dateien arbeitest. Das Handbuch öffnet sich offline im Browser.' if de else
                           'Keep this help open while working with files. The German handbook opens offline in your browser.')
        titles = {'anfang': ('Anwenderhandbuch öffnen', 'Open user handbook (German)'),
                  'tastatur': ('Tastenkürzel und Bedienung', 'Keyboard shortcuts and controls'),
                  'cloud': ('Cloud-Dienste verbinden', 'Connect cloud services'),
                  'uebertragungen': ('Kopieren, Pause und Fortsetzen', 'Copy, pause and resume'),
                  'probleme': ('Probleme lösen', 'Troubleshooting')}
        present = handbook_path().is_file()
        for anchor, button in self.buttons.items():
            button.setText(titles[anchor][0 if de else 1])
            button.setEnabled(present)
        shortcuts = [('F5 / F6', 'In den anderen Bereich kopieren / verschieben', 'Copy / move to the other pane'),
                     ('Strg+L / Ctrl+L', 'Pfad eingeben', 'Enter a path'),
                     ('Alt+↑', 'Eine Ebene höher; Herkunftsordner wird markiert', 'Go up and select the folder you came from'),
                     ('Strg+F / Ctrl+F', 'Dateien auch in Unterordnern suchen', 'Search files including subfolders'),
                     ('Esc', 'Aktiven Dateifilter löschen (Fokus im Filterfeld)', 'Clear file filter (while the filter field is focused)'),
                     ('Leertaste / Space', 'Ausgewählte Datei in der Vorschau öffnen', 'Preview the selected file'),
                     ('Strg+, / Ctrl+,', 'Einstellungen und Orte', 'Settings and locations')]
        rows = ''.join(f'<tr><td><b>{key}</b></td><td>{german if de else english}</td></tr>' for key, german, english in shortcuts)
        self.shortcuts.setHtml('<table cellpadding="7">' + rows + '</table>')
        self.notice.setText('' if present else ('Das Handbuch fehlt im Paket. Die Kurzhilfe oben bleibt verfügbar.' if de else
                                               'The handbook is missing from this package. Quick help remains available above.'))
        self.close_button.setText('Schließen' if de else 'Close')

    def open_chapter(self, anchor):
        if anchor not in self.buttons:
            return
        url = QUrl.fromLocalFile(str(handbook_path()))
        url.setFragment(anchor)
        if not handbook_path().is_file() or not QDesktopServices.openUrl(url):
            self.notice.setText(('Handbuch konnte nicht geöffnet werden. Datei: ' if self.main.language == 'de' else
                                 'Could not open handbook. File: ') + str(handbook_path()))
