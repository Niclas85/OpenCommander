"""Concurrent durable transfers; controls never wait for provider I/O."""
import os
import time
from pathlib import Path
from collections import Counter

from PySide6.QtCore import Qt, QThreadPool, QTimer
from PySide6.QtWidgets import (QApplication, QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
                              QToolButton, QScrollArea, QProgressBar, QSpinBox, QFrame, QSizePolicy)
from .operations import Cancelled
from .formatting import human_duration


class TransferTitle(QLabel):
    """Keep full accessible text while painting a single elided line."""
    def paintEvent(self, event):
        from PySide6.QtGui import QPainter
        painter = QPainter(self)
        painter.setFont(self.font())
        painter.setPen(self.palette().color(self.foregroundRole()))
        text = self.fontMetrics().elidedText(self.text(), Qt.ElideMiddle, self.contentsRect().width())
        painter.drawText(self.contentsRect(), Qt.AlignLeft | Qt.AlignVCenter, text)


def resources(job):
    # Lexical paths plus local symlink aliases. Never resolve inside a provider.
    from .filesystem import remote_location
    def normalized(value):
        path = Path(os.path.abspath(value))
        if os.name == 'nt':
            from .platform_support import canonical_path
            return canonical_path(path)
        prefix = Path(path.anchor)
        parts = path.parts[1:]
        for index, part in enumerate(parts):
            prefix = prefix / part
            if remote_location(prefix):
                return prefix.joinpath(*parts[index+1:])
            if prefix.is_symlink():
                link = prefix.readlink()
                prefix = Path(os.path.abspath(link if link.is_absolute() else prefix.parent / link))
                if remote_location(prefix):
                    return prefix.joinpath(*parts[index+1:])
        return prefix
    sources = [(Path(os.path.abspath(p)), bool(job.get('move'))) for p in job['sources']]
    targets = [Path(job['directory']) / Path(p).name for p in job['sources']]
    targets += [Path(root['target']) for root in job.get('roots') or [] if root.get('target')]
    paths = sources + [(p, True) for p in targets]
    return paths + [(normalized(p), write) for p, write in paths]


def conflicts(left, right):
    import re
    def family(path):
        # Keep-both may choose "photo (2).jpg" in the worker. Reserve that
        # filename family too, without statting a destination in the GUI.
        return Path(*(re.sub(r'(?: \([0-9]+\))+(?=\.[^.]+$|$)', '', part) for part in path.parts))
    left = left + [(family(path), write) for path, write in left]
    right = right + [(family(path), write) for path, write in right]
    return any((aw or bw) and (a == b or a in b.parents or b in a.parents)
               for a, aw in left for b, bw in right)


class TransferCard(QFrame):
    def __init__(self, manager, job):
        super().__init__()
        self.manager, self.job = manager, job
        self.setObjectName('historyCard')
        self.state = job['status'] if job['status'] != 'running' else 'paused'
        self.metrics = job.get('progress')
        self.started = None
        self.pause_requested_at = None
        self.previous_elapsed = job.get('elapsed', 0)
        self.error = job.get('error') or ''
        self.reserved = resources(job)
        self.task = self.engine = None
        self.pending_metrics = None
        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 3, 8, 3)
        layout.setSpacing(4)
        top = QHBoxLayout()
        self.title = TransferTitle()
        self.title.setObjectName('transferTitle')
        self.title.setTextFormat(Qt.PlainText)
        self.title.setWordWrap(False)
        top.addWidget(self.title, 1)
        self.progress = QProgressBar()
        self.progress.setTextVisible(False)
        self.progress.setFixedWidth(90)
        top.addWidget(self.progress, 0, Qt.AlignVCenter)
        self.minimize = QToolButton()
        self.minimize.setCheckable(True)
        self.minimize.setToolButtonStyle(Qt.ToolButtonIconOnly)
        top.addWidget(self.minimize)
        self.pause = QPushButton()
        self.resume = QPushButton()
        self.cancel = QPushButton()
        for button in (self.pause, self.resume, self.cancel):
            top.addWidget(button)
        self.pause.clicked.connect(lambda: manager.pause_one(job['id']))
        self.resume.clicked.connect(lambda: manager.resume_one(job['id']))
        self.cancel.clicked.connect(lambda: manager.cancel_one(job['id']))
        layout.addLayout(top)
        self.route = QLabel(', '.join(job['sources']) + ' → ' + job['directory'])
        self.route.setTextFormat(Qt.PlainText)
        self.route.setWordWrap(True)
        self.route.setToolTip(self.route.text())
        layout.addWidget(self.route)
        self.details = QLabel()
        self.details.setTextFormat(Qt.PlainText)
        self.details.setWordWrap(True)
        self.details.setTextInteractionFlags(Qt.TextSelectableByMouse)
        layout.addWidget(self.details)
        # Long cloud paths must wrap within the viewport, rather than forcing
        # the whole card (including its controls) beyond the visible width.
        for label in (self.title, self.route, self.details):
            policy = label.sizePolicy()
            policy.setHorizontalPolicy(QSizePolicy.Ignored)
            label.setSizePolicy(policy)
            label.setMinimumWidth(0)
        self.copy_details = QPushButton()
        self.copy_details.clicked.connect(self.copy_report)
        layout.addWidget(self.copy_details, 0, Qt.AlignLeft)
        self.minimize.setChecked(manager.window.settings.value(
            'transfer_minimized/' + job['id'], True, type=bool))
        self.minimize.toggled.connect(self.set_minimized)
        self.set_minimized(self.minimize.isChecked(), save=False)
        self.render()

    def set_minimized(self, minimized, save=True):
        self.route.setVisible(not minimized)
        self.details.setVisible(not minimized)
        self.copy_details.setVisible(not minimized)
        self.minimize.setArrowType(Qt.DownArrow if minimized else Qt.UpArrow)
        if save:
            self.manager.window.settings.setValue('transfer_minimized/' + self.job['id'], minimized)
        self.render()
        if save:
            self.manager.render()

    def render(self):
        from .ui import human_size
        if self.pending_metrics and self.pending_metrics[0] is not None:
            self.metrics = self.pending_metrics[0]
        language = self.manager.window.language
        # Settled cards need no repeated text/layout work. Active elapsed time
        # only changes once per second; fresh metrics still render at 250 ms.
        render_key = (language, self.manager.window.closing, self.state, self.error,
                      self.minimize.isChecked(), self.metrics, self.previous_elapsed,
                      int(time.monotonic() - self.started) if self.started else None)
        if getattr(self, '_render_key', None) == render_key:
            return self.details.text()
        self._render_key = render_key
        de = language == 'de'
        self.copy_details.setText('Details kopieren' if de else 'Copy details')
        self.copy_details.setToolTip('Status und Fehler in die Zwischenablage kopieren. Enthält Quell- und Zielpfade.' if de else
                                    'Copy status and error to the clipboard. Includes source and destination paths.')
        states = {
            'queued': ('Wartend', 'Queued'), 'waiting': ('Wartet auf freien Quell-/Zielpfad', 'Waiting for source/destination'),
            'running': ('Läuft', 'Running'), 'pausing': ('Pause angefordert · warte auf Dateizugriff', 'Pause requested · waiting for file access'),
            'paused': ('Pausiert – gespeichert', 'Paused – saved'),
            'cancelling': ('Abbruch angefordert · warte auf Dateizugriff / Bereinigung', 'Cancel requested · waiting for file access / cleanup'),
            'cancelled': ('Abgebrochen', 'Cancelled'), 'blocked': ('Angehalten – Fehler · Details unten', 'Stopped – error · details below'),
            'complete': ('Abgeschlossen', 'Completed')}
        kind = ('Verschieben' if self.job.get('move') else 'Kopieren') if de else ('Move' if self.job.get('move') else 'Copy')
        name = ', '.join(Path(p).name for p in self.job['sources'])
        state = states[self.state][0 if de else 1]
        minimized = self.minimize.isChecked()
        if minimized and len(self.job['sources']) > 1:
            name = Path(self.job['sources'][0]).name + f' · {len(self.job["sources"])} ' + ('Elemente' if de else 'items')
        if minimized and self.state == 'blocked':
            state = 'Angehalten – Fehler · Details öffnen' if de else 'Stopped – error · open details'
        if self.title.property('transferState') != self.state:
            self.title.setProperty('transferState', self.state)
            self.title.style().unpolish(self.title)
            self.title.style().polish(self.title)
        self.title.setText(f'{kind} · {name} · {state}')
        self.minimize.setText(('Details' if minimized else 'Minimieren') if de else ('Details' if minimized else 'Minimize'))
        self.minimize.setToolTip(('Details anzeigen' if minimized else 'Kompakt anzeigen – Auftrag läuft weiter') if de else
                                ('Show details' if minimized else 'Show compact view – transfer keeps running'))
        self.minimize.setAccessibleName(self.minimize.toolTip())
        self.pause.setText('Pause')
        self.pause.setToolTip('Stoppt vor dem nächsten Datenblock. Laufender Netzwerkzugriff und Upload-Abschluss müssen noch enden.' if de else
                              'Stops before the next data block. Pending network access and upload finalization must finish first.')
        self.resume.setText('Fortsetzen' if de else 'Resume')
        self.cancel.setText('Abbrechen' if de else 'Cancel')
        self.pause.setVisible(self.state in ('running', 'pausing'))
        self.pause.setEnabled(self.state == 'running' and not self.manager.window.closing)
        self.resume.setVisible(self.state in ('paused', 'blocked'))
        self.resume.setEnabled(not self.manager.window.closing)
        self.cancel.setVisible(self.state not in ('complete', 'cancelled'))
        self.cancel.setEnabled(self.state != 'cancelling' and not self.manager.window.closing)
        value = self.metrics
        details = state
        if value:
            count, total = value['bytes_done'], value['bytes_total']
            phase = value['phase']
            percent = 100 if self.state == 'complete' else min(99, int(count * 100 / total)) if total else min(99, int(value['files_done'] * 100 / value['files_total'])) if value['files_total'] else 0
            elapsed = self.previous_elapsed + (time.monotonic() - self.started if self.started else 0)
            self.progress.setRange(0, 0 if phase == 'planning' and self.state == 'running' else 100)
            self.progress.setValue(percent)
            phases = {'planning': ('Dateien und Größe ermitteln', 'Counting files and size'),
                      'resuming': ('Gespeicherten Stand prüfen · kein erneutes Kopieren', 'Checking saved progress · not copying again'),
                      'checking_partial': ('Angefangene Datei prüfen', 'Checking partial file'),
                      'verifying': ('Prüfen und abschließen', 'Verifying and finalizing'),
                      'uploading': ('Schreiben abschließen / Upload', 'Finishing writes / upload'),
                      'cleanup': ('Quelle bereinigen', 'Cleaning up source')}
            label = phases.get(phase, (kind, kind))[0 if de else 1]
            if minimized:
                self.title.setText(f'{kind} · {name} · {state} · {percent}% · {human_size(count)} / {human_size(total)}')
            rate = max(0, count - value.get('bytes_resumed', 0)) / max(time.monotonic() - self.started, .001) if self.started else getattr(self, 'last_rate', 0) if self.state == 'complete' else 0
            remaining = max(0, total-count) / rate if rate and total > count and self.state == 'running' and phase == 'copying' else None
            clock = lambda seconds: human_duration(seconds, language)
            eta = f' · {"Rest ca." if de else "Remaining ~"} {clock(remaining)}' if remaining is not None else ''
            details = (f'{label} · {percent}% · {human_size(count)} / {human_size(total)} · '
                           f'{value["files_done"]} / {value["files_total"]} {"Dateien" if de else "files"}\n'
                           f'{"Zeit insgesamt (aktiv)" if de else "Total active time"} {clock(elapsed)} · {human_size(rate)}/s{eta}\n{value["name"]}')
            if phase == 'resuming' and value.get('resume_files_total'):
                checked = value.get('resume_bytes_checked', 0)
                check_total = value.get('resume_bytes_total', 0)
                check_percent = min(100, int(checked * 100 / check_total)) if check_total else min(100, int(
                    value.get('resume_files_checked', 0) * 100 / value['resume_files_total']))
                self.progress.setValue(check_percent)
                checking = 'Prüfung' if de else 'Verification'
                copied = 'Bereits kopiert' if de else 'Already copied'
                details = (f'{label} · {checking} {check_percent}%\n'
                           f'{copied}: {human_size(count)} / {human_size(total)} · '
                           f'{value["files_done"]} / {value["files_total"]} {"Dateien" if de else "files"}\n'
                           f'{"Zeit insgesamt (aktiv)" if de else "Total active time"} {clock(elapsed)}\n{value["name"]}')
                if minimized:
                    self.title.setText(f'{kind} · {name} · {state} · {checking} {check_percent}% · {human_size(count)} {copied.lower()}')
                details += (f'\n{"Geprüft" if de else "Checked"}: '
                            f'{value.get("resume_files_checked", 0)} / {value["resume_files_total"]} '
                            f'{"gespeicherte Dateien" if de else "saved files"} · '
                            f'{human_size(value.get("resume_bytes_checked", 0))} / '
                            f'{human_size(value.get("resume_bytes_total", 0))}')
                if value.get('verification_source') == 'provider':
                    details += ('\nDirekte Cloud-Prüfsumme bestätigt' if de else '\nDirect cloud checksum verified')
        else:
            self.progress.setRange(0, 0 if self.state == 'running' else 100)
            self.progress.setValue(0)
        if self.state == 'pausing' and self.pause_requested_at is not None:
            waiting = human_duration(time.monotonic() - self.pause_requested_at, language)
            details += (f'\nPause wird vorbereitet · Wartezeit {waiting}\n'
                        'Es werden keine weiteren Datenblöcke gestartet. Der laufende Dateizugriff bzw. Upload-Abschluss muss enden. '
                        'Erst „Pausiert – gespeichert“ bestätigt den gesicherten Stand. Andere Bereiche bleiben bedienbar.' if de else
                        f'\nPreparing pause · Waiting {waiting}\n'
                        'No further data blocks will start. Pending file access or upload finalization must finish. '
                        'Only “Paused – saved” confirms the saved state. Other areas remain available.')
        if self.error:
            details += '\n' + self.error
        elif self.job.get('last_error'):
            details += '\n' + ('Letzter Fehler vor Fortsetzung: ' if de else 'Last error before resume: ') + self.job['last_error']
        self.details.setText(details)
        self.title.setToolTip(self.route.text() + '\n' + details)
        self.progress.setToolTip(details)
        return details

    def copy_report(self):
        from . import __version__
        details = self.render()
        from .platform_support import PLATFORM_NAME
        QApplication.clipboard().setText(f'OpenCommander {PLATFORM_NAME} {__version__}\n'
            f'ID: {self.job["id"]}\n{self.title.text()}\n{self.route.text()}\n{details}')
        self.manager.window.status.setText('Details kopiert (mit Dateipfaden).' if self.manager.window.language == 'de' else
                                           'Details copied (including file paths).')


class TransferOverview(QWidget):
    def __init__(self, window):
        super().__init__(window)
        self.setObjectName('transferOverview')
        self.setAttribute(Qt.WA_StyledBackground, True)
        self.window = window
        if not window.settings.value('transfer_compact_layout_v1', False, type=bool):
            # Replace the old expanded-card default once; later user choices persist.
            for key in window.settings.allKeys():
                if key.startswith('transfer_minimized/'):
                    window.settings.setValue(key, True)
            window.settings.setValue('transfer_expanded', True)
            window.settings.setValue('transfer_compact_layout_v1', True)
        self.cards = {}
        self.active = {}
        self.generic_running = False
        self.pool = QThreadPool(self)
        self.pool.setMaxThreadCount(4)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        self.toggle = QToolButton()
        self.toggle.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self.toggle.setCheckable(True)
        self.toggle.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        header = QHBoxLayout()
        header.addWidget(self.toggle, 1)
        self.body = QWidget()
        self.body.setObjectName('transferBody')
        self.body.setAttribute(Qt.WA_StyledBackground, True)
        body = QVBoxLayout(self.body)
        body.setContentsMargins(0, 0, 0, 0)
        self.parallel_label = QLabel()
        header.addWidget(self.parallel_label)
        self.parallel = QSpinBox()
        self.parallel.setRange(1, 4)
        self.parallel.setValue(window.settings.value('transfer_parallel', 2, type=int))
        header.addWidget(self.parallel)
        self.clear_button = QPushButton()
        self.clear_button.clicked.connect(self.clear_completed)
        header.addWidget(self.clear_button)
        layout.addLayout(header)
        self.scroll = QScrollArea()
        self.scroll.setObjectName('transferScroll')
        self.scroll.setWidgetResizable(True)
        self.scroll.setMinimumHeight(38)
        self.scroll.setFrameShape(QFrame.NoFrame)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.items = QWidget()
        self.items.setObjectName('transferItems')
        self.rows = QVBoxLayout(self.items)
        self.rows.setContentsMargins(0, 0, 0, 0)
        self.rows.setSpacing(3)
        self.rows.addStretch()
        self.scroll.setWidget(self.items)
        body.addWidget(self.scroll)
        layout.addWidget(self.body)
        self.toggle.toggled.connect(self.set_expanded)
        self.toggle.setChecked(window.settings.value('transfer_expanded', True, type=bool))
        self.set_expanded(self.toggle.isChecked(), save=False)
        self.parallel.valueChanged.connect(self.limit_changed)
        self.timer = QTimer(self)
        self.timer.setInterval(250)
        self.timer.timeout.connect(self.render)
        self.hide()

    def set_expanded(self, expanded, save=True):
        self.body.setVisible(expanded)
        self.parallel_label.setVisible(expanded)
        self.parallel.setVisible(expanded)
        self.toggle.setArrowType(Qt.DownArrow if expanded else Qt.RightArrow)
        if save:
            self.window.settings.setValue('transfer_expanded', expanded)
        if hasattr(self, 'timer'):
            self.render()
        if save and hasattr(self.window, 'transfers'):
            self.window.resize_transfer_panel(expanded)

    def limit_changed(self, value):
        self.window.settings.setValue('transfer_parallel', value)
        self.pump()

    def add(self, job):
        if job['id'] not in self.cards:
            card = TransferCard(self, job)
            self.cards[job['id']] = card
            self.rows.insertWidget(self.rows.count()-1, card)
            if len(self.cards) > 1 and not self.window.settings.contains('transfer_expanded'):
                self.toggle.setChecked(True)
        self.show()
        return self.cards[job['id']]

    def submit(self, identifier, after=None):
        job = self.window.engine.transfers.get(identifier)
        if not job or identifier in self.active:
            return
        card = self.add(job)
        card.job = job
        if job.get('error'):
            card.job['last_error'] = job['error']
        card.after = after
        card.state, card.error = 'queued', ''
        if identifier not in {row[2] for row in self.window.operation_queue}:
            self.window.operation_queue.append((None, after, identifier))
        self.pump()

    def sync_busy(self):
        w = self.window
        if w.busy and not w.operation_running and not self.active and not self.generic_running:
            return  # A drive-disconnect worker owns the existing busy state.
        w.busy = bool(self.active) or self.generic_running
        w.operation_running = w.busy
        w.active_transfer_id = next(iter(self.active), None)
        w.actions['undo'].setEnabled(bool(w.engine.history) and not w.busy)
        for card in w.history_cards.values():
            if w.busy:
                card.undo_button.setEnabled(False)

    def can_run_file_action(self, callback):
        reserved = getattr(callback, 'reserved', None)
        if reserved is None or self.generic_running:
            return False
        # Saved/paused transfers also retain their sources and destinations.
        return not any(conflicts(reserved, card.reserved) for card in self.cards.values()
                       if card.state not in ('complete', 'cancelled'))

    def pump(self):
        w = self.window
        if w.closing or self.generic_running or (w.busy and not w.operation_running):
            self.sync_busy()
            self.render()
            return
        for callback, after, identifier in list(w.operation_queue):
            if identifier is None:
                if (self.can_run_file_action(callback) if hasattr(callback, 'reserved') else not self.active and not w.transfers_paused):
                    w.operation_queue.remove((callback, after, identifier))
                    w.run_operation(callback, after)
                break
            if w.transfers_paused:
                continue
            if len(self.active) >= self.parallel.value():
                break
            card = self.cards[identifier]
            prior = [c for c in self.cards.values() if c is not card and c.state not in ('complete', 'cancelled')
                     and (c.job['created'] < card.job['created'] or c.job['id'] in self.active)]
            if any(conflicts(card.reserved, c.reserved) for c in prior):
                card.state = 'waiting'
                continue
            w.operation_queue.remove((callback, after, identifier))
            self.start(card)
        self.sync_busy()
        self.render()

    def start(self, card, discard=False):
        from .ui import Task
        w = self.window
        engine = w.engine if not any(c.engine is w.engine for c in self.active.values()) and not self.generic_running else w.engine.fork()
        engine.cancel.clear()
        engine.pause.clear()
        engine.progress = lambda *_: None
        card.engine = engine
        card.state = 'cancelling' if discard else 'running'
        card.started = time.monotonic()
        card.pause_requested_at = None
        card.previous_elapsed = card.job.get('elapsed', 0)
        # Keep saved progress while mount checks or worker startup are pending.
        if card.metrics:
            card.metrics = dict(card.metrics, bytes_resumed=card.metrics['bytes_done'],
                                phase=card.metrics['phase'] if discard else 'resuming')
        identifier = card.job['id']
        self.active[identifier] = card
        w.status.setText(w.tr_key('working'))
        def work():
            if discard:
                from .resumable_copy import discard as remove
                return remove(engine, identifier)
            return w.run_copy_job(identifier, engine)
        task = Task(work)
        card.task = task
        pending = [None]
        card.pending_metrics = pending
        def report(value):
            # Replace one immutable snapshot; only the GUI timer touches widgets.
            # Even a blocked syscall leaves the last completed block visible.
            pending[0] = value
        engine.metrics_report = report
        task.signals.result.connect(lambda value, error: self.done(card, value, error), Qt.QueuedConnection)
        self.pool.start(task)
        self.sync_busy()

    def done(self, card, value, error):
        w = self.window
        identifier = card.job['id']
        saved = w.engine.transfers.get(identifier)
        if card.pending_metrics and card.pending_metrics[0] is not None:
            card.metrics = card.pending_metrics[0]
        card.pending_metrics = None
        duration = time.monotonic() - card.started
        card.last_rate = max(0, card.metrics['bytes_done'] - card.metrics.get('bytes_resumed', 0)) / max(duration, .001) if card.metrics else 0
        card.previous_elapsed += duration
        card.started = None
        card.state = saved['status'] if saved else 'cancelled' if isinstance(error, Cancelled) or card.state == 'cancelling' else 'complete'
        if saved:
            card.job = saved
            card.reserved = resources(saved)
            card.error = saved.get('error') or ''
            card.metrics = saved.get('progress') or card.metrics
        else:
            w.settings.remove('transfer_minimized/' + identifier)
            card.error = str(error) if error and not isinstance(error, Cancelled) else '\n'.join(value.get('warnings', [])) if isinstance(value, dict) else ''
        card.engine.metrics_report = lambda _: None
        card.engine.progress = lambda *_: None
        self.active.pop(identifier, None)
        card.engine = card.task = None
        self.sync_busy()
        details = card.render()
        if not self.active:
            w.transfer_details.setText(card.title.text() if card.minimize.isChecked() else details)
            w.transfer_details.show()
            w.progress.hide()
        w.status.setText(card.title.text())
        if not w.closing:
            w.reload_history()
            if hasattr(w, 'cloud_listings'):
                w.cloud_listings.invalidate()
            w.refresh_all()
        if not error and getattr(card, 'after', None) and not w.closing:
            card.after(value)
        w.operation_finished.emit(error)
        self.pump()
        if not w.busy and not w.operation_queue:
            w.cancel_requested = False

    def pause_one(self, identifier):
        card = self.cards[identifier]
        if identifier in self.active and card.state == 'running':
            card.state = 'pausing'
            card.pause_requested_at = time.monotonic()
            card.engine.pause.set()
            card.engine.cancel.set()
        elif identifier not in self.active and card.state in ('queued', 'waiting'):
            self.window.operation_queue[:] = [row for row in self.window.operation_queue if row[2] != identifier]
            card.state = 'paused'
            card.job['status'] = 'paused'
            self.window.engine.transfers.save(card.job)
        self.render()

    def pause_all(self):
        self.window.transfers_paused = True
        for identifier in self.cards:
            self.pause_one(identifier)
        self.render()

    def resume_one(self, identifier):
        if self.window.closing or identifier in self.active:
            return
        self.window.transfers_paused = False
        self.submit(identifier, getattr(self.cards[identifier], 'after', None))

    def restore(self, automatic=False):
        w = self.window
        if w.closing or w.engine.transfers.error:
            return
        w.transfers_paused = False
        for job in w.engine.transfers.jobs():
            self.add(job)
            if job['id'] not in self.active and (not automatic or job['status'] != 'blocked'):
                self.submit(job['id'])
        self.pump()

    def cancel_one(self, identifier):
        if self.window.closing:
            return
        card = self.cards[identifier]
        if identifier in self.active:
            card.engine.pause.clear()
            card.engine.cancel.set()
            card.state = 'cancelling'
        elif card.state not in ('complete', 'cancelled'):
            self.window.operation_queue[:] = [row for row in self.window.operation_queue if row[2] != identifier]
            self.start(card, discard=True)
        self.render()

    def cancel_all(self):
        w = self.window
        queued = list(w.operation_queue)
        w.operation_queue.clear()
        for callback, _, identifier in queued:
            if identifier is None and getattr(callback, 'finished', None):
                callback.finished(None, Cancelled('Abgebrochen / Cancelled'))
        w.transfers_paused = False
        w.cancel_requested = True
        if self.generic_running:
            self.generic_engine.pause.clear()
            self.generic_engine.cancel.set()
        for job in w.engine.transfers.jobs():
            self.add(job)
        for identifier, card in self.cards.items():
            if card.state not in ('complete', 'cancelled'):
                self.cancel_one(identifier)
        self.sync_busy()
        self.render()

    def clear_completed(self):
        for identifier, card in list(self.cards.items()):
            if card.state in ('complete', 'cancelled'):
                self.rows.removeWidget(card)
                card.deleteLater()
                self.cards.pop(identifier)
                self.window.settings.remove('transfer_minimized/' + identifier)
        self.setVisible(bool(self.cards))
        self.render()

    def render(self):
        w = self.window
        de = w.language == 'de'
        counts = Counter(card.state for card in self.cards.values())
        active = len(self.active)
        queued = len(w.operation_queue)
        paused = counts['paused'] + counts['blocked']
        parts = []
        if active:
            parts.append(f'{active} {"aktiv" if de else "active"}')
        if queued:
            parts.append(f'{queued} {"wartend" if de else "queued"}')
        if paused:
            parts.append(f'{paused} {"gespeichert" if de else "saved"}')
        if counts['blocked']:
            parts.append(f'{counts["blocked"]} {"Fehler" if de else "errors"}')
        self.toggle.setText(('Übertragungen' if de else 'Transfers') + ' · ' + (' · '.join(parts) or f'{counts["complete"]} {"abgeschlossen" if de else "completed"}'))
        self.parallel_label.setText('Gleichzeitig:' if de else 'Parallel:')
        self.clear_button.setText('Abgeschlossene ausblenden' if de else 'Hide completed')
        self.clear_button.setVisible(self.toggle.isChecked() and bool(counts['complete'] or counts['cancelled']))
        w.queue_label.setToolTip('\n'.join(getattr(row[0], 'label', 'Dateivorgang / File operation') for row in w.operation_queue if row[2] is None))
        w.queue_label.setText(' · '.join(parts[1:] if active else parts) or (f'{len(w.operation_queue)} wartend' if w.operation_queue else ''))
        w.pause_button.setVisible(bool(active) and not w.closing)
        w.pause_button.setText('Alle pausieren' if de else 'Pause all')
        w.pause_button.setEnabled(any(card.state == 'running' for card in self.active.values()))
        w.resume_button.setVisible(bool(paused or w.transfers_paused) and not w.closing)
        w.resume_button.setText('Alle fortsetzen' if de else 'Resume all')
        w.resume_button.setEnabled(True)
        w.cancel_button.setVisible(w.busy or bool(paused or queued))
        for card in self.cards.values():
            details = card.render()
            if active == 1 and card.job['id'] in self.active and not self.generic_running:
                w.transfer_details.setText(card.title.text() + ('' if card.minimize.isChecked() else '\n' + details))
                w.transfer_details.show()
                w.progress.setRange(card.progress.minimum(), card.progress.maximum())
                w.progress.setValue(card.progress.value())
                w.progress.show()
        if active and not self.timer.isActive():
            self.timer.start()
        elif not active:
            self.timer.stop()
        if active > 1 and not self.generic_running:
            w.transfer_details.setText(self.toggle.text())
            w.transfer_details.show()
            w.progress.hide()
        # Expanded cards already contain progress and details. Keep the legacy
        # summary only when the overview is collapsed (or for generic actions).
        if self.cards and not self.generic_running:
            w.transfer_details.hide()
            w.progress.hide()
        if hasattr(w, 'transfer_area'):
            visible = bool(self.cards) or not w.transfer_details.isHidden()
            was_hidden = w.transfer_area.isHidden()
            w.transfer_area.setVisible(visible)
            geometry_key = (self.toggle.isChecked(), tuple(card.minimize.isChecked() for card in self.cards.values()))
            if visible and (was_hidden or (geometry_key != getattr(self, '_geometry_key', None) and not w.settings.contains('transfer_panel_height'))):
                w.resize_transfer_panel(self.toggle.isChecked())
            self._geometry_key = geometry_key
