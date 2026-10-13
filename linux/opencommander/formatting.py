"""Shared, unambiguous duration labels for long-running operations."""
import math


def human_duration(seconds, language='de'):
    if not math.isfinite(seconds):
        return '—'
    seconds = max(0, int(seconds))
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    parts = []
    if days:
        parts.append(f'{days} ' + ('Tag' if days == 1 else 'Tage') if language == 'de'
                     else f'{days} ' + ('day' if days == 1 else 'days'))
    if hours or days:
        parts.append(f'{hours} h')
    if minutes or hours or days:
        parts.append(f'{minutes} min')
    parts.append(f'{seconds} s')
    return ' '.join(parts)
