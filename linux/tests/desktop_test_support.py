"""Compare private storage using the host operating system's permission model."""
import os


def assert_private_file(path):
    if os.name != 'nt':
        assert path.stat().st_mode & 0o777 == (0o700 if path.is_dir() else 0o600)
        return
    import ntsecuritycon
    import win32api
    import win32con
    import win32security
    token = win32security.OpenProcessToken(win32api.GetCurrentProcess(), win32con.TOKEN_QUERY)
    try:
        owner = win32security.GetTokenInformation(token, win32security.TokenUser)[0]
    finally:
        token.Close()
    allowed = {str(owner), str(win32security.CreateWellKnownSid(win32security.WinLocalSystemSid, None))}
    acl = win32security.GetNamedSecurityInfo(str(path), win32security.SE_FILE_OBJECT,
                                            win32security.DACL_SECURITY_INFORMATION).GetSecurityDescriptorDacl()
    assert acl is not None and acl.GetAceCount()
    for index in range(acl.GetAceCount()):
        kind, mask, sid = acl.GetAce(index)
        if kind[0] == win32security.ACCESS_ALLOWED_ACE_TYPE and mask & ntsecuritycon.FILE_READ_DATA:
            assert str(sid) in allowed
