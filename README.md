<p align="center">
  <img src="https://raw.githubusercontent.com/Niclas85/OpenCommander/codex/linux-desktop/website/assets/github-banner.svg" alt="OpenCommander – Zwei Seiten. Alles im Blick. Android, iOS, Windows, Linux und macOS" width="100%">
</p>

<p align="center">
  Ein kostenloser, quelloffener Dateimanager für unterwegs und am Schreibtisch.<br>
  Zwei Dateiansichten. Direkte Wege. Deine Dateien unter deiner Kontrolle.
</p>

<p align="center">
  <a href="https://opencommander.top"><strong>Webseite</strong></a> ·
  <a href="https://opencommander.top/#plattformen">Deine Version</a> ·
  <a href="https://opencommander.top/docs/">Dokumentation</a> ·
  <a href="https://github.com/Niclas85/OpenCommander/issues">Fehler & Ideen</a>
</p>

## Ein Projekt. Drei Bereiche. Fünf Plattformen.

OpenCommander verbindet die Idee eines klassischen Commanders mit Oberflächen für **Android**, **iPhone/iPad** und **Desktop**. Die Plattformen haben eigene Integrationen und unterschiedliche Entwicklungsstände. Hier findest du den passenden Einstieg:

| Bereich | Plattform | Verfügbarkeit | Einstieg |
| :-- | :-- | :-- | :-- |
| Android | Android 8 und neuer | Auf Google Play | [Android-App](https://play.google.com/store/apps/details?id=com.opencommander) |
| iPhone & iPad | iOS / iPadOS 16 und neuer | Im App Store | [iPhone- und iPad-App](https://apps.apple.com/de/app/opencommander/id6804432999) |
| Desktop | Windows | Entwicklungsstand, unter Windows 11 x64 praktisch geprüft | [Windows-Anleitung](https://opencommander.top/docs/#windows) |
| Desktop | Linux | Entwicklungsstand, Build für Ubuntu 24.04 x86_64 dokumentiert | [Linux-Anleitung](https://opencommander.top/docs/#linux) |
| Desktop | macOS | Apple-Silicon-Vorschau | [macOS-Preview](https://github.com/Niclas85/OpenCommander/releases/tag/macos-v1.2-preview.20260912) |

> **Stand: 15. Oktober 2026.** Windows und Linux werden derzeit im Branch [`codex/linux-desktop`](https://github.com/Niclas85/OpenCommander/tree/codex/linux-desktop) entwickelt. Für diese beiden Plattformen ist noch kein öffentliches Release-Paket auf GitHub veröffentlicht. Die macOS-Version ist ausdrücklich eine Vorschau.

## Dateien bewegen, ohne den Überblick zu verlieren

- **Zwei Ansichten:** Quelle und Ziel direkt nebeneinander – auf dem Handy passend zum verfügbaren Platz.
- **Dateien organisieren:** kopieren, verschieben, umbenennen, Ordner anlegen und Mehrfachauswahl.
- **Archive bearbeiten:** ZIP-Funktionen; weitere Formate und Möglichkeiten je nach Plattform.
- **Direkt arbeiten:** Drag & Drop, Kontextaktionen und Rückgängig für unterstützte Dateiaktionen.
- **Eigene Daten:** lokale Dateien und die von dir freigegebenen Speicherorte.
- **Offener Quellcode:** kostenlos unter der MIT-Lizenz, ohne Werbung oder Tracking in der App.

## 01 · Android

Für Smartphone, Tablet und Android TV. Im Hochformat stehen die beiden Dateiseiten untereinander, im Querformat nebeneinander. Ordnerbäume, Mehrfachauswahl, ZIP, Drag & Drop und Rückgängig unterstützen die tägliche Dateiarbeit.

**[Bei Google Play öffnen](https://play.google.com/store/apps/details?id=com.opencommander)** · [Android-Quellcode](https://github.com/Niclas85/OpenCommander/tree/main/app)

## 02 · iPhone & iPad

Die native Apple-App arbeitet mit den Ordnern, die du ihr über die iOS-Dateiauswahl freigibst. Dazu kommen Zugänge für Fotos, Videos und Musik, Vorschauen sowie Exportfunktionen für unterstützte Medien.

Die iOS-Sandbox bleibt wirksam: OpenCommander erhält keinen allgemeinen Zugriff auf andere Apps oder das gesamte Dateisystem. Musikexport ist auf lokal verfügbare, nicht geschützte Inhalte begrenzt.

**[Im App Store öffnen](https://apps.apple.com/de/app/opencommander/id6804432999)** · [Apple-Quellcode](https://github.com/Niclas85/OpenCommander/tree/main/ios)

## 03 · Desktop: Windows, Linux & macOS

**Windows und Linux** teilen sich die Qt-Oberfläche. Zu ihren Funktionen gehören Registerkarten, Dateiübertragungen mit Warteschlange, Suche, Vorschauen, Verzeichnisvergleich, Archivwerkzeuge sowie Verbindungen zu Servern und Cloud-Speichern. Die Betriebssystem-Anbindung unterscheidet sich: etwa WinFsp und Windows-Anmeldeinformationen unter Windows beziehungsweise GVFS/FUSE unter Linux.

**macOS** basiert auf der Apple-App mit Mac-Catalyst-Anpassungen, Mac-Tastenkürzeln, Quick Look und „Öffnen mit“. Die veröffentlichte Vorschau ist für Apple Silicon. Ihr Funktionsumfang entspricht nicht in allen Punkten dem Qt-Desktop.

<p align="center">
  <img src="https://raw.githubusercontent.com/Niclas85/OpenCommander/codex/linux-desktop/website/assets/desktop-dark.png" alt="OpenCommander Qt unter Linux: zwei Dateiansichten, Ordnerbäume und dunkles Design" width="100%">
  <br><sub>Originalabbildung aus dem Linux-Handbuch. Die Windows-Version nutzt dieselbe Qt-Oberfläche mit eigenen Systemintegrationen.</sub>
</p>

[Windows: Installation & Build](https://github.com/Niclas85/OpenCommander/blob/codex/linux-desktop/windows/README.md) · [Linux: Installation & Build](https://github.com/Niclas85/OpenCommander/blob/codex/linux-desktop/linux/README.md) · [macOS-Release](https://github.com/Niclas85/OpenCommander/releases/tag/macos-v1.2-preview.20260912)

## Dokumentation, die dich weiterbringt

- **[Dokumentationsportal](https://opencommander.top/docs/)** – Einstieg, Systemvoraussetzungen und Unterschiede zwischen den Plattformen.
- **[Desktop-Handbuch](https://opencommander.top/docs/handbuch/)** – 18 Kapitel mit 20 Abbildungen, lokaler Suche, Themenwechsel und Druckansicht.
- **[Windows-Teststand](https://github.com/Niclas85/OpenCommander/blob/codex/linux-desktop/windows/TESTING.md)** – praktische Prüfungen, Voraussetzungen und offene Punkte.
- **[Entwicklung & technische Hinweise](DEVELOPMENT.md)** – Build-Anleitungen und Projektstruktur.

Das eingebundene Handbuch dokumentiert Linux 0.3.21. Neuere Windows-Änderungen bis zum Entwicklungsstand 0.3.25-rc10 sind in der Windows-Dokumentation beschrieben. Externe Dienste können eigene Anmeldungen, Freigaben oder Prüfungen verlangen; insbesondere ist die öffentliche Google-OAuth-Verifizierung ein separater Vorgang.

## Mitmachen

Fehler gefunden oder eine Idee? [Öffne ein Issue](https://github.com/Niclas85/OpenCommander/issues) und nenne Plattform, App-Version und nachvollziehbare Schritte. Bitte veröffentliche keine Passwörter, Tokens oder privaten Dateien.

Beiträge sind willkommen. Lies die [Hinweise für Beiträge](CONTRIBUTING.md) und die [Sicherheitshinweise](SECURITY.md). Für Desktop-Änderungen ist aktuell `codex/linux-desktop` der relevante Branch.

---

[Webseite](https://opencommander.top) · [Datenschutz](https://opencommander.top/privacy) · [Impressum](https://opencommander.top/impressum) · [Kontakt](mailto:info@opengames.vip)

OpenCommander wird von Niklaus Haenggi entwickelt und unter der [MIT-Lizenz](LICENSE) veröffentlicht.
