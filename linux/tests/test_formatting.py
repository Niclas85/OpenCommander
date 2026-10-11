import pytest
from opencommander.formatting import human_duration


@pytest.mark.parametrize('seconds,expected', [
    (0, '0 s'), (59.9, '59 s'), (60, '1 min 0 s'), (3599, '59 min 59 s'),
    (3600, '1 h 0 min 0 s'), (7385, '2 h 3 min 5 s'),
    (90061, '1 Tag 1 h 1 min 1 s'), (172800, '2 Tage 0 h 0 min 0 s'),
    (-10, '0 s'), (float('inf'), '—'), (float('nan'), '—'),
])
def test_duration_boundaries(seconds, expected):
    assert human_duration(seconds) == expected


def test_english_days():
    assert human_duration(86400, 'en') == '1 day 0 h 0 min 0 s'
    assert human_duration(172800, 'en') == '2 days 0 h 0 min 0 s'
