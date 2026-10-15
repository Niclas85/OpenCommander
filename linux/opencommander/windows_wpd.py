"""Windows Portable Devices COM adapter (no Explorer automation or extra drivers).

All objects belong to the calling COM apartment. The mount helper owns that
apartment and serializes device requests. ABI definitions follow Microsoft's
PortableDeviceApi.h / PortableDeviceTypes.h; only the interfaces used here are
bound. Device errors are never converted into empty directories or success.
"""
import ctypes as C
from contextlib import contextmanager
import io
import uuid

U32, I32, U64, PTR = C.c_uint32, C.c_int32, C.c_uint64, C.c_void_p


class GUID(C.Structure):
    _fields_ = [('data', C.c_ubyte * 16)]

    def __init__(self, value=None):
        super().__init__()
        if value:
            self.data[:] = uuid.UUID(value).bytes_le

    def __str__(self):
        return str(uuid.UUID(bytes_le=bytes(self.data)))


class Key(C.Structure):
    _fields_ = [('fmtid', GUID), ('pid', U32)]


class VariantData(C.Union):
    _fields_ = [('pointer', PTR), ('integer', U64), ('date', C.c_double),
                ('alignment', U64 * 2)]


class Variant(C.Structure):
    _fields_ = [('vt', C.c_uint16), ('reserved', C.c_uint16 * 3), ('value', VariantData)]


OBJECT = 'ef6b490d-5cd8-437a-affc-da8b60ee4a3c'
CLIENT = '204d9f0c-2292-4080-9f42-40664e70f859'
FOLDER = '27e2e392-a111-48e0-ab0c-e17705a05f85'
FUNCTIONAL = '99ed0160-17ff-4c44-9d98-1d7a6f941921'
STORAGE = '23f05bbc-15de-4c2a-a55b-a9af5ce412ef'
GENERIC_FILE = '0085e0a6-8d34-45d7-bc5c-447e59c73d48'
RESOURCE = Key(GUID('e81e79be-34f0-41bf-b53f-f1a06ae87842'), 0)
FUNCTION = Key(GUID('8f052d93-abca-4fc5-a5ac-b01df4dbe598'), 2)
KEYS = {name: Key(GUID(OBJECT), number) for name, number in
        [('parent', 3), ('name', 4), ('format', 6), ('type', 7), ('size', 11),
         ('filename', 12), ('modified', 19)]}


def checked(hr):
    if hr < 0:
        number = hr & 0xffffffff
        if number == 0x80070005:
            raise PermissionError('Gerät gesperrt oder Zugriff verweigert / Device locked or access denied')
        raise OSError(f'Windows Portable Devices: HRESULT 0x{number:08x}')
    return hr


def ole():
    result = C.OleDLL('ole32')
    result.CoTaskMemFree.argtypes = [PTR]
    result.CoTaskMemFree.restype = None
    return result


@contextmanager
def apartment():
    library = ole()
    # Dedicated helpers and test workers own their apartment; never change the GUI's.
    checked(library.CoInitializeEx(None, 0))
    try:
        yield
    finally:
        library.CoUninitialize()


def take_string(pointer):
    try:
        return C.wstring_at(pointer) if pointer.value else ''
    finally:
        ole().CoTaskMemFree(pointer)


class Com:
    def __init__(self, pointer):
        self.pointer = pointer if isinstance(pointer, PTR) else PTR(pointer)

    @classmethod
    def create(cls, class_id, interface):
        pointer = PTR()
        checked(ole().CoCreateInstance(C.byref(GUID(class_id)), None, 1,
                                      C.byref(GUID(interface)), C.byref(pointer)))
        return cls(pointer)

    def call(self, index, types=(), args=()):
        if not self.pointer.value:
            raise RuntimeError('COM object closed')
        table = C.cast(self.pointer, C.POINTER(C.POINTER(PTR))).contents
        method = C.WINFUNCTYPE(I32, PTR, *types)(table[index])
        return checked(method(self.pointer, *args))

    def output(self, index, types=(), args=(), cls=None):
        pointer = PTR()
        self.call(index, (*types, C.POINTER(PTR)), (*args, C.byref(pointer)))
        if not pointer.value:
            raise OSError('WPD returned no object')
        return (cls or Com)(pointer)

    def query(self, interface):
        return self.output(0, (C.POINTER(GUID),), (C.byref(GUID(interface)),))

    def close(self):
        if self.pointer.value:
            table = C.cast(self.pointer, C.POINTER(C.POINTER(PTR))).contents
            C.WINFUNCTYPE(U32, PTR)(table[2])(self.pointer)
            self.pointer = PTR()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


class Values(Com):
    @classmethod
    def new(cls):
        return cls.create('0c15d503-d017-47ce-9016-7b3f978721cc',
                          '6848f6f2-3155-4f86-b6f5-263eeeab3143')

    def string(self, key):
        pointer = PTR()
        self.call(8, (C.POINTER(Key), C.POINTER(PTR)), (C.byref(key), C.byref(pointer)))
        return take_string(pointer)

    def number(self, key):
        value = U64()
        self.call(14, (C.POINTER(Key), C.POINTER(U64)), (C.byref(key), C.byref(value)))
        return value.value

    def guid(self, key):
        value = GUID()
        self.call(28, (C.POINTER(Key), C.POINTER(GUID)), (C.byref(key), C.byref(value)))
        return str(value)

    def set_string(self, key, value):
        self.call(7, (C.POINTER(Key), C.c_wchar_p), (C.byref(key), value))

    def set_number(self, key, value):
        self.call(13, (C.POINTER(Key), U64), (C.byref(key), value))

    def set_guid(self, key, value):
        self.call(27, (C.POINTER(Key), C.POINTER(GUID)), (C.byref(key), C.byref(GUID(value))))

    def optional(self, method, key, default):
        try:
            return getattr(self, method)(key)
        except OSError:
            return default

    def modified(self):
        value = Variant()
        try:
            self.call(6, (C.POINTER(Key), C.POINTER(Variant)),
                      (C.byref(KEYS['modified']), C.byref(value)))
            if value.vt == 7:  # VT_DATE, days since 1899-12-30
                return max(0, (value.value.date - 25569) * 86400)
            if value.vt == 64:  # VT_FILETIME
                return max(0, value.value.integer / 10000000 - 11644473600)
            return 0
        except OSError:
            return 0
        finally:
            ole().PropVariantClear(C.byref(value))


def devices():
    """Enumerate WPD devices, including locked ones, without opening their data."""
    with apartment(), Com.create('0af10cec-2ecd-4b92-9581-34f6ae0637f3',
                                 'a1567595-4c2f-4574-a6fa-ecef917b9a40') as manager:
        manager.call(4)
        count = U32()
        manager.call(3, (PTR, C.POINTER(U32)), (None, C.byref(count)))
        if count.value > 4096:
            raise OSError('Too many portable devices')
        pointers = (PTR * count.value)()
        try:
            manager.call(3, (PTR, C.POINTER(U32)), (pointers, C.byref(count)))
            result = []
            for pointer in pointers[:count.value]:
                identifier = C.wstring_at(pointer)
                length = U32()
                manager.call(5, (C.c_wchar_p, PTR, C.POINTER(U32)),
                             (identifier, None, C.byref(length)))
                if not 0 < length.value < 32768:
                    raise OSError('Invalid portable device name')
                name = C.create_unicode_buffer(length.value)
                manager.call(5, (C.c_wchar_p, PTR, C.POINTER(U32)),
                             (identifier, name, C.byref(length)))
                result.append(dict(id=identifier, name=name.value or 'MTP / WPD'))
            return result
        finally:
            for pointer in pointers:
                ole().CoTaskMemFree(pointer)


@contextmanager
def object_ids(identifier):
    with Com.create('08a99e2f-6d6d-4b80-af5a-baf2bcbe4cb9',
                    '89b2e422-4f1b-4316-bcef-a44afea83eb3') as collection:
        text = C.create_unicode_buffer(identifier)
        value = Variant()
        value.vt = 31  # VT_LPWSTR; Add copies it, caller owns text.
        value.value.pointer = C.cast(text, PTR)
        collection.call(5, (C.POINTER(Variant),), (C.byref(value),))
        yield collection


def result_status(results):
    count = U32()
    results.call(3, (C.POINTER(U32),), (C.byref(count),))
    if count.value != 1:
        raise OSError('WPD mutation returned no individual result')
    value = Variant()
    try:
        results.call(4, (U32, C.POINTER(Variant)), (0, C.byref(value)))
        if value.vt != 10:
            raise OSError('WPD mutation result is not an HRESULT')
        checked(I32(value.value.integer & 0xffffffff).value)
    finally:
        ole().PropVariantClear(C.byref(value))


class Device:
    def __init__(self, identifier):
        self.identifier = identifier
        self.device = self.content = self.properties = self.resources = None

    def __enter__(self):
        try:
            self.device = Com.create('728a21c5-3d9e-48d7-9810-864848f0f404',
                                     '625e2df8-6392-4cf0-9ad1-3cfa5f17775c')
            with Values.new() as client:
                client.set_string(Key(GUID(CLIENT), 2), 'OpenCommander')
                self.device.call(3, (C.c_wchar_p, PTR), (self.identifier, client.pointer))
            self.content = self.device.output(5)
            self.properties = self.content.output(4)
            self.resources = self.content.output(5)
            return self
        except BaseException:
            self.close()
            raise

    def close(self):
        for item in (self.resources, self.properties, self.content, self.device):
            if item:
                item.close()

    def __exit__(self, *_):
        self.close()

    def info(self, identifier):
        with self.properties.output(5, (C.c_wchar_p, PTR), (identifier, None), Values) as values:
            kind = values.guid(KEYS['type'])
            storage = kind == FUNCTIONAL and values.optional('guid', FUNCTION, '') == STORAGE
            name = values.optional('string', KEYS['filename'], '') or values.string(KEYS['name'])
            return dict(id=identifier, name=name, parent=values.string(KEYS['parent']), directory=kind == FOLDER or storage,
                        storage=storage, size=0 if kind in (FOLDER, FUNCTIONAL) else values.number(KEYS['size']),
                        modified=values.modified())

    def children(self, parent):
        result = []
        with self.content.output(3, (U32, C.c_wchar_p, PTR), (0, parent, None)) as enumeration:
            while True:
                pointers, fetched = (PTR * 64)(), U32()
                try:
                    enumeration.call(3, (U32, PTR, C.POINTER(U32)), (64, pointers, C.byref(fetched)))
                    if fetched.value > 64:
                        raise OSError('Invalid WPD enumeration')
                    for pointer in pointers[:fetched.value]:
                        info = self.info(C.wstring_at(pointer))
                        # Device-level services (contacts, SMS, etc.) are not files.
                        if parent != 'DEVICE' or info['storage']:
                            result.append(info)
                    if fetched.value < 64:
                        return result
                finally:
                    for pointer in pointers:
                        ole().CoTaskMemFree(pointer)

    @contextmanager
    def read(self, identifier):
        size, pointer = U32(), PTR()
        self.resources.call(5, (C.c_wchar_p, C.POINTER(Key), U32, C.POINTER(U32), C.POINTER(PTR)),
                            (identifier, C.byref(RESOURCE), 0, C.byref(size), C.byref(pointer)))
        with Com(pointer) as stream:
            class Reader(io.RawIOBase):
                def read(self, amount=-1):
                    if amount < 0:
                        raise ValueError('Device reads must be bounded')
                    data, count = C.create_string_buffer(amount), U32()
                    stream.call(3, (PTR, U32, C.POINTER(U32)), (data, amount, C.byref(count)))
                    return data.raw[:count.value]
            yield Reader()

    def values(self, parent, name, directory=False, size=0):
        result = Values.new()
        try:
            result.set_string(KEYS['parent'], parent)
            result.set_string(KEYS['name'], name)
            result.set_string(KEYS['filename'], name)
            result.set_guid(KEYS['type'], FOLDER if directory else GENERIC_FILE)
            result.set_guid(KEYS['format'], '30010000-ae6c-4804-98ba-c57b46965fe7' if directory
                            else '30000000-ae6c-4804-98ba-c57b46965fe7')
            if not directory:
                result.set_number(KEYS['size'], size)
            return result
        except BaseException:
            result.close()
            raise

    def mkdir(self, parent, name):
        with self.values(parent, name, True) as values:
            pointer = PTR()
            self.content.call(6, (PTR, C.POINTER(PTR)), (values.pointer, C.byref(pointer)))
            return take_string(pointer)

    def create(self, parent, name, source, size):
        with self.values(parent, name, size=size) as values:
            pointer, optimal, cookie = PTR(), U32(), PTR()
            try:
                self.content.call(7, (PTR, C.POINTER(PTR), C.POINTER(U32), C.POINTER(PTR)),
                                  (values.pointer, C.byref(pointer), C.byref(optimal), C.byref(cookie)))
            finally:
                ole().CoTaskMemFree(cookie)
        with Com(pointer) as stream, stream.query('88e04db3-1012-4d64-9996-f703a950d3f4') as device_stream:
            committed = False
            try:
                left = size
                while left:
                    block = source.read(min(left, 1024 * 1024))
                    if not block:
                        raise EOFError('Incomplete device upload')
                    data, count = C.create_string_buffer(block), U32()
                    stream.call(4, (PTR, U32, C.POINTER(U32)), (data, len(block), C.byref(count)))
                    if count.value != len(block):
                        raise OSError('Incomplete WPD write')
                    left -= count.value
                stream.call(8, (U32,), (0,))  # IStream::Commit
                committed = True
                pointer = PTR()
                device_stream.call(14, (C.POINTER(PTR),), (C.byref(pointer),))
                return take_string(pointer)
            except BaseException:
                if not committed:
                    try:
                        device_stream.call(15)  # Cancel only the uncommitted stream.
                    except OSError:
                        pass
                raise

    def rename(self, identifier, name):
        info = self.info(identifier)
        with Values.new() as values:
            key = KEYS['name'] if info['directory'] else KEYS['filename']
            values.set_string(key, name)
            with self.properties.output(6, (C.c_wchar_p, PTR), (identifier, values.pointer), Values) as results:
                error = I32()
                results.call(20, (C.POINTER(Key), C.POINTER(I32)), (C.byref(key), C.byref(error)))
                checked(error.value)
        if self.info(identifier)['name'] != name:
            raise OSError('Device did not apply the requested filename')

    def move(self, identifier, parent):
        with object_ids(identifier) as ids:
            with self.content.output(11, (PTR, C.c_wchar_p), (ids.pointer, parent)) as results:
                result_status(results)

    def delete(self, identifier):
        # No recursion: the filesystem engine removes children explicitly.
        with object_ids(identifier) as ids:
            with self.content.output(8, (U32, PTR), (0, ids.pointer)) as results:
                result_status(results)
