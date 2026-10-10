"""Read archive formats through libarchive; extraction writes only regular files."""
from contextlib import contextmanager
from dataclasses import dataclass
import io
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import zipfile

if getattr(sys, 'frozen', False):
    os.environ['LIBARCHIVE'] = str(Path(sys._MEIPASS) / 'libarchive.so.13')
import libarchive
from .operations import SafetyError, checked_members

EXTENSIONS = ('.zip', '.7z', '.rar', '.tar', '.tgz', '.tar.gz', '.tbz', '.tbz2',
              '.tar.bz2', '.txz', '.tar.xz', '.tar.zst')


def is_archive(path):
    return str(path).lower().endswith(EXTENSIONS)


@dataclass
class Member:
    filename: str
    file_size: int
    external_attr: int
    directory: bool
    flag_bits: int = 0
    def is_dir(self):
        return self.directory


class BlockStream(io.RawIOBase):
    def __init__(self, blocks):
        super().__init__()
        self.blocks = iter(blocks)
        self.pending = memoryview(b'')
    def readable(self):
        return True
    def readinto(self, buffer):
        if not self.pending:
            self.pending = memoryview(next(self.blocks, b''))
        count = min(len(buffer), len(self.pending))
        buffer[:count] = self.pending[:count]
        self.pending = self.pending[count:]
        return count


class NativeArchive:
    def __init__(self, path):
        self.path = str(path)
        self.members = None
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def infolist(self):
        if self.members is None:
            members = []
            total = 0
            with libarchive.file_reader(self.path) as stream:
                for entry in stream:
                    name = entry.pathname
                    if entry.isdir and name in ('.', './'):
                        continue  # Ordinary TAR root marker, never an output path.
                    name = str(PurePosixPath(name)) + ('/' if entry.isdir else '')
                    mode = entry.mode
                    if entry.linkpath or not (entry.isdir or entry.isreg):
                        mode = stat.S_IFLNK
                    size = entry.size or 0
                    if size < 0:
                        raise SafetyError('Invalid archive size')
                    total += size
                    if len(members) >= 100_000 or total > 4 * 1024**3:
                        raise SafetyError('Archive limit: 100,000 entries / 4 GiB unpacked')
                    members.append(Member(name, size, mode << 16, entry.isdir))
            self.members = members
        return self.members
    def getinfo(self, name):
        return next(member for member in self.infolist() if member.filename == name)
    def blocks(self, selected):
        expected = {str(PurePosixPath(member.filename)): member for member in selected}
        with libarchive.file_reader(self.path) as stream:
            for entry in stream:
                key = str(PurePosixPath(entry.pathname))
                member = expected.get(key)
                if member is None:
                    continue
                if entry.linkpath or not (entry.isdir or entry.isreg) or (entry.size or 0) != member.file_size:
                    raise SafetyError('Archive changed while reading')
                del expected[key]
                yield member, entry.get_blocks()
        if expected:
            raise SafetyError('Archive members no longer exist')
    @contextmanager
    def open(self, member):
        if isinstance(member, str):
            member = self.getinfo(member)
        for info, blocks in self.blocks([member]):
            with io.BufferedReader(BlockStream(blocks)) as stream:
                yield stream
            return
        raise SafetyError('Archive member no longer exists')


def open_archive(path):
    return zipfile.ZipFile(path) if str(path).lower().endswith('.zip') else NativeArchive(path)


def member_blocks(archive, selected):
    if isinstance(archive, NativeArchive):
        yield from archive.blocks(selected)
    else:
        for member in selected:
            if member.is_dir():
                yield member, iter(())
            else:
                with archive.open(member) as stream:
                    yield member, iter(lambda: stream.read(1024 * 1024), b'')
