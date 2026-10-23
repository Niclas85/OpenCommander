import pytest
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QMessageBox
from test_ui import app, window

from opencommander.external_links import MORE_APPS_URL, open_more_apps


@pytest.mark.parametrize('language', ['de', 'en'])
def test_more_apps_help_and_settings_are_explicit(window, monkeypatch, language):
    opened = []
    monkeypatch.setattr(QDesktopServices, 'openUrl', lambda url: opened.append(url.toString()) or True)
    window.change_language(language)
    window.help()
    window.location_settings()
    assert opened == []  # No automatic request on launch or opening a panel.
    for dialog in [window.help_dialog, window.location_settings_dialog]:
        assert 'haenggi.vip' in dialog.more_apps_button.text()
        assert ('Weitere Apps' if language == 'de' else 'More apps') in dialog.more_apps_button.text()
        dialog.more_apps_button.click()
    assert opened == [MORE_APPS_URL, MORE_APPS_URL]
    assert MORE_APPS_URL == 'https://haenggi.vip/'


def test_more_apps_missing_browser_is_reported(app, monkeypatch):
    warnings = []
    monkeypatch.setattr(QDesktopServices, 'openUrl', lambda url: False)
    monkeypatch.setattr(QMessageBox, 'warning', lambda *args: warnings.append(args))
    open_more_apps(None, 'de')
    assert len(warnings) == 1
    assert 'https://haenggi.vip/' in warnings[0][2]
