"""Browse recoverable OpenCommander removals without accessing offline volumes."""
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QDialog, QVBoxLayout, QLabel, QTreeWidget, QTreeWidgetItem, QPushButton


class TrashDialog(QDialog):
    def __init__(self, main):
        super().__init__(main)
        self.main = main
        de = main.language == 'de'
        self.setWindowTitle('OpenCommander-Papierkorb' if de else 'OpenCommander Trash')
        self.resize(850, 480)
        layout = QVBoxLayout(self)
        note = QLabel('Hier erscheinen die mit OpenCommander entfernten Dateien. Wiederherstellen gilt für den ausgewählten Löschvorgang.\n'
                      'Dies ist unabhängig vom System-Papierkorb. Das ursprüngliche Laufwerk muss verbunden sein.' if de else
                      'Files removed with OpenCommander appear here. Restore applies to the selected removal operation.\n'
                      'This is separate from the system trash. The original drive must be connected.')
        note.setWordWrap(True)
        layout.addWidget(note)
        self.items = QTreeWidget()
        self.items.setHeaderLabels(['Name', 'Ursprünglicher Pfad' if de else 'Original path', 'Entfernt am' if de else 'Removed at'])
        self.items.setColumnWidth(0, 230)
        self.items.setColumnWidth(1, 390)
        layout.addWidget(self.items)
        self.restore_button = QPushButton('Löschvorgang wiederherstellen' if de else 'Restore removal operation')
        self.restore_button.clicked.connect(self.restore)
        layout.addWidget(self.restore_button)
        self.status = QLabel()
        self.status.setWordWrap(True)
        layout.addWidget(self.status)
        self.items.itemSelectionChanged.connect(self.selection_changed)
        main.operation_finished.connect(self.operation_done)
        self.refresh()

    def refresh(self):
        self.items.clear()
        for operation in reversed(self.main.engine.history):
            if operation['label'] != 'trash':
                continue
            for record in operation['records']:
                if record.get('reverted'):
                    continue
                source = record['source']
                item = QTreeWidgetItem([Path(source).name, source,
                    datetime.fromtimestamp(operation['time']).strftime('%d.%m.%Y %H:%M:%S')])
                item.setData(0, Qt.UserRole, operation['id'])
                item.setToolTip(0, record['destination'])
                self.items.addTopLevelItem(item)
        self.selection_changed()

    def selection_changed(self):
        self.restore_button.setEnabled(bool(self.items.currentItem()) and not self.main.busy)

    def restore(self):
        item = self.items.currentItem()
        if item and not self.main.busy:
            self.status.setText('Wiederherstellung läuft … / Restoring …')
            self.main.undo(item.data(0, Qt.UserRole))
            self.selection_changed()

    def operation_done(self, error):
        self.refresh()
        self.status.setText(str(error) if error else 'Fertig / Done')
