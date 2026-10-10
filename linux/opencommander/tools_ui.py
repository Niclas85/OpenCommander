"""Asynchronous search, comparison and preview-first batch rename dialogs."""
import threading
import time
from pathlib import Path
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (QDialog, QVBoxLayout, QHBoxLayout, QLineEdit, QLabel,
    QPushButton, QCheckBox, QTreeWidget, QTreeWidgetItem, QProgressBar, QSpinBox)
from shiboken6 import isValid
from . import commander_tools as tools


class ToolsDialog(QDialog):
    def __init__(self, main, mode):
        super().__init__(main)
        self.main, self.mode = main, mode
        self.cancel = threading.Event()
        self.pending = False
        self.plan = None
        self.paths = [entry.path for entry in main.active.selected()]
        self.de = main.language == 'de'
        title = {'search': ('Dateien suchen', 'Search files'), 'compare': ('Ordner vergleichen', 'Compare folders'),
                 'rename': ('Mehrfach umbenennen', 'Multi-rename')}[mode]
        self.setWindowTitle(self.t(*title))
        self.resize(940, 600)
        layout = QVBoxLayout(self)
        self.path = QLineEdit(str(main.active.directory))
        if mode == 'search':
            layout.addWidget(QLabel(self.t('Suchpfad', 'Search path')))
            layout.addWidget(self.path)
            self.query = QLineEdit()
            self.query.setPlaceholderText(self.t('Teilname oder Muster mit * und ?', 'Part of name or pattern with * and ?'))
            layout.addWidget(self.query)
            self.sensitive = QCheckBox(self.t('Groß-/Kleinschreibung beachten', 'Case sensitive'))
            layout.addWidget(self.sensitive)
        elif mode == 'compare':
            layout.addWidget(QLabel('\n'.join(str(pane.directory) for pane in main.panes)))
            layout.addWidget(QLabel(self.t('SHA-256-Inhaltsvergleich kann Cloud-Dateien herunterladen.',
                                          'SHA-256 content comparison may download cloud files.')))
        else:
            self.pattern = QLineEdit('[N][E]')
            self.find = QLineEdit()
            self.replacement = QLineEdit()
            for label, widget in [('Muster [N] Name · [E] Erweiterung · [C] Zähler' if self.de else
                                   'Pattern [N] Name · [E] Extension · [C] Counter', self.pattern),
                                  (self.t('Suchen', 'Find'), self.find), (self.t('Ersetzen', 'Replace'), self.replacement)]:
                layout.addWidget(QLabel(label))
                layout.addWidget(widget)
                widget.textChanged.connect(self.invalidate)
            row = QHBoxLayout()
            self.start = QSpinBox()
            self.start.setRange(0, 2147480000)
            self.start.setValue(1)
            self.digits = QSpinBox()
            self.digits.setRange(1, 9)
            self.digits.setValue(3)
            for label, widget in [(self.t('Start', 'Start'), self.start), (self.t('Stellen', 'Digits'), self.digits)]:
                row.addWidget(QLabel(label)); row.addWidget(widget)
                widget.valueChanged.connect(self.invalidate)
            layout.addLayout(row)
        self.items = QTreeWidget()
        self.items.setHeaderLabels([self.t('Name / Pfad', 'Name / Path'), self.t('Ergebnis', 'Result')])
        self.items.setColumnWidth(0, 620)
        self.items.itemDoubleClicked.connect(self.open_result)
        layout.addWidget(self.items)
        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.hide()
        layout.addWidget(self.progress)
        self.status = QLabel()
        self.status.setWordWrap(True)
        layout.addWidget(self.status)
        row = QHBoxLayout()
        self.run_button = QPushButton(self.t('Vorschau', 'Preview') if mode == 'rename' else self.t('Starten', 'Start'))
        self.run_button.clicked.connect(self.run)
        row.addWidget(self.run_button)
        self.apply_button = QPushButton(self.t('Umbenennen anwenden', 'Apply rename'))
        self.apply_button.setVisible(mode == 'rename')
        self.apply_button.setEnabled(False)
        self.apply_button.clicked.connect(self.apply)
        row.addWidget(self.apply_button)
        self.cancel_button = QPushButton(self.t('Abbrechen', 'Cancel'))
        self.cancel_button.clicked.connect(lambda: self.cancel.set())
        self.cancel_button.setEnabled(False)
        row.addWidget(self.cancel_button)
        layout.addLayout(row)

    def t(self, de, en):
        return de if self.de else en

    def invalidate(self, *args):
        self.plan = None
        if hasattr(self, 'apply_button'):
            self.apply_button.setEnabled(False)

    def run(self):
        if self.pending:
            return
        from .ui import Task
        self.cancel = threading.Event()
        self.pending = True
        self.invalidate()
        self.items.clear()
        self.run_button.setEnabled(False)
        self.cancel_button.setEnabled(True)
        self.progress.show()
        hidden, cancel = self.main.hidden, self.cancel
        if self.mode == 'search':
            root = self.path.text()
            query, sensitive = self.query.text(), self.sensitive.isChecked()
            work = lambda: tools.search(tools.search_directory(root), query, hidden, sensitive, cancel, report)
        elif self.mode == 'compare':
            left, right = [pane.directory for pane in self.main.panes]
            work = lambda: tools.compare(left, right, hidden, cancel, report)
        else:
            rule = self.pattern.text(), self.find.text(), self.replacement.text(), self.start.value(), self.digits.value()
            work = lambda: tools.rename_plan(self.paths, *rule)
        task = Task(work)
        last_report = [0.0]
        def report(count, name):
            now = time.monotonic()
            if now - last_report[0] >= 0.1:
                last_report[0] = now
                task.signals.progress.emit(count, name)
        task.signals.progress.connect(lambda count, name: self.status.setText(f'{count} · {name}'))
        def done(value, error):
            self.pending = False
            self.progress.hide()
            self.run_button.setEnabled(True)
            self.cancel_button.setEnabled(False)
            if error:
                self.status.setText(str(error))
                return
            if self.mode == 'rename':
                self.plan = value
                for row in value:
                    self.items.addTopLevelItem(QTreeWidgetItem([str(row.source), row.destination.name]))
                # Editing while a preview runs invalidates its result.
                current = self.pattern.text(), self.find.text(), self.replacement.text(), self.start.value(), self.digits.value()
                self.apply_button.setEnabled(current == rule)
                if current != rule:
                    self.plan = None
                self.status.setText(self.t('Vorschau prüfen, dann anwenden.', 'Review the preview, then apply.'))
            else:
                rows, warnings = value
                states = {'equal': self.t('Gleich', 'Equal'), 'different': self.t('Unterschiedlich', 'Different'),
                          'left': self.t('Nur links', 'Left only'), 'right': self.t('Nur rechts', 'Right only'),
                          'unreadable': self.t('Nicht lesbar', 'Unreadable')}
                for result in rows:
                    if self.mode == 'search':
                        item = QTreeWidgetItem([f'{result.name}\n{result.path}', ''])
                        item.setData(0, Qt.UserRole, str(result.path))
                    else:
                        name, state, detail = result
                        item = QTreeWidgetItem([name, states[state]])
                        item.setToolTip(1, detail)
                    self.items.addTopLevelItem(item)
                self.status.setText(f'{len(rows)} ' + self.t('Ergebnisse', 'results') +
                                    ('\n' + self.t('Unvollständig: ', 'Incomplete: ') + '\n'.join(warnings[:20]) if warnings else ''))
        task.signals.result.connect(done)
        self.main.start_background(task)

    def open_result(self, item, column):
        path = item.data(0, Qt.UserRole)
        if path:
            self.main.active.navigate(Path(path).parent)

    def apply(self):
        if self.plan and not self.main.busy and self.apply_button.isEnabled():
            plan = self.plan
            self.invalidate()
            self.main.run_operation(lambda: tools.rename_batch(self.main.engine, plan))
            self.accept()

    def closeEvent(self, event):
        if self.pending:
            self.cancel.set()
            event.ignore()
        else:
            super().closeEvent(event)

    def reject(self):
        if self.pending:
            self.cancel.set()
        else:
            super().reject()
