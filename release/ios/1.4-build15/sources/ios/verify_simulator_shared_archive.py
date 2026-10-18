"""Independently validate the ZIP produced by SharedFolderFileOperationsTests."""
import argparse
import hashlib
import json
from pathlib import Path
import unicodedata
import zipfile


def verify(root):
    expected = {
        'Beweis.txt': b'Copy, Move, ZIP on iOS\n',
        'Unterordner/Grüsse 日本語.txt': 'äöü — 日本語\n'.encode(),
        'Unterordner/data.bin': bytes(i % 251 for i in range(1_048_576)),
        'empty.txt': b'',
    }
    digest = lambda data: hashlib.sha256(data).hexdigest()
    hashes = {name: digest(data) for name, data in expected.items()}
    source = root / 'Source' / 'Folder'
    actual = {unicodedata.normalize('NFC', str(p.relative_to(source))): digest(p.read_bytes())
              for p in source.rglob('*') if p.is_file()}
    assert actual == hashes, 'Original source was changed'
    assert (source / 'Leer').is_dir(), 'Original empty directory missing'
    assert not (root / 'CopyTarget' / 'Folder').exists(), 'Copy Undo incomplete'
    assert not (root / 'MoveTarget' / 'Folder').exists(), 'Move Undo incomplete'
    archive_path = root / 'Source' / 'Folder.zip'
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.testzip() is None, 'ZIP CRC validation failed'
        assert len(archive.namelist()) == len(set(archive.namelist())), 'Duplicate ZIP names'
        actual = {unicodedata.normalize('NFC', name.removeprefix('Folder/')):
                  digest(archive.read(name)) for name in archive.namelist() if not name.endswith('/')}
        assert actual == hashes, 'Archive file names or contents differ'
        assert 'Folder/Leer/' in archive.namelist(), 'Empty directory missing from archive'
    return {'status': 'passed', 'archive': str(archive_path), 'fileSHA256': hashes,
            'crcVerified': True, 'sourceUnchanged': True, 'emptyDirectoryPreserved': True,
            'copyAndMoveUndoVerified': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixture', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.fixture)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    print('PASS: ZIP CRC, all file hashes, Unicode names, empty directory and Undo cleanup')
