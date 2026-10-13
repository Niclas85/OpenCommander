from pathlib import Path
import io
import tarfile
import libarchive
import pytest
from opencommander.archives import open_archive, is_archive
from opencommander.filesystem import archive_listing
from opencommander.operations import FileEngine, checked_members, SafetyError


@pytest.mark.parametrize('kind,filter,suffix', [('ustar','gzip','.tgz'), ('ustar','bzip2','.tar.bz2'),
                                             ('ustar','xz','.tar.xz'), ('7zip',None,'.7z')])
def test_native_archive_browse_preview_extract_and_undo(tmp_path, kind, filter, suffix):
    archive_path = tmp_path / ('fixture' + suffix)
    contents = b'archive fixture content'
    with libarchive.file_writer(str(archive_path), kind, filter) as writer:
        writer.add_file_from_memory('folder/hello.txt', len(contents), contents)
    assert is_archive(archive_path)
    root = archive_listing(archive_path)
    assert root[0].name == 'folder' and root[0].directory
    child = archive_listing(archive_path, 'folder/')[0]
    assert child.member == 'folder/hello.txt'
    with open_archive(archive_path) as archive:
        checked_members(archive)
        with archive.open(archive.getinfo(child.member)) as stream:
            assert stream.read() == contents
    destination = tmp_path / 'out'; destination.mkdir()
    engine = FileEngine(tmp_path / 'state')
    engine.extract_zip(archive_path, destination)
    assert (destination / 'folder/hello.txt').read_bytes() == contents
    engine.undo()
    assert not (destination / 'folder').exists()
    assert archive_path.exists()


def test_real_rar5_fixture_browse_and_extract(tmp_path):
    archive_path = Path(__file__).parent / 'fixtures/rar5-stored.rar'
    entries = archive_listing(archive_path)
    assert entries[0].name == 'helloworld.txt' and entries[0].size == 29
    destination = tmp_path / 'out'; destination.mkdir()
    engine = FileEngine(tmp_path / 'state')
    engine.extract_zip(archive_path, destination)
    assert (destination / 'helloworld.txt').stat().st_size == 29
    engine.undo()
    assert not (destination / 'helloworld.txt').exists()


@pytest.mark.parametrize('attack', ['traversal', 'symlink', 'hardlink', 'special', 'duplicate'])
def test_tar_rejects_unsafe_members_before_publishing(tmp_path, attack):
    archive_path = tmp_path / 'unsafe.tgz'
    with tarfile.open(archive_path, 'w:gz') as archive:
        regular = tarfile.TarInfo('safe.txt'); regular.size=4
        archive.addfile(regular, io.BytesIO(b'safe'))
        bad = tarfile.TarInfo('../escape' if attack == 'traversal' else 'safe.txt' if attack == 'duplicate' else 'bad')
        if attack in ('symlink', 'hardlink'):
            bad.type = tarfile.SYMTYPE if attack == 'symlink' else tarfile.LNKTYPE
            bad.linkname = '../escape'
        elif attack == 'special':
            bad.type = tarfile.FIFOTYPE
        archive.addfile(bad)
    destination = tmp_path / 'out'; destination.mkdir()
    engine = FileEngine(tmp_path / 'state')
    with pytest.raises(SafetyError):
        engine.extract_zip(archive_path, destination)
    assert not list(destination.iterdir())
    assert not (tmp_path / 'escape').exists()
    assert not engine.history


def test_tar_dot_paths_and_selected_subdirectory(tmp_path):
    archive_path=tmp_path/'fixture.tar'
    with tarfile.open(archive_path,'w') as archive:
        root=tarfile.TarInfo('./');root.type=tarfile.DIRTYPE;archive.addfile(root)
        for name in ('./folder/chosen.txt','./other.txt'):
            entry=tarfile.TarInfo(name);entry.size=1;archive.addfile(entry,io.BytesIO(b'x'))
    assert [entry.name for entry in archive_listing(archive_path)] == ['folder','other.txt']
    destination=tmp_path/'out';destination.mkdir()
    FileEngine(tmp_path/'state').extract_zip(archive_path,destination,['folder/'])
    assert (destination/'folder/chosen.txt').read_bytes()==b'x'
    assert not (destination/'other.txt').exists()
