#!/usr/bin/env python3
"""Read-only audit of a portable package, without extracting or running it."""
import argparse
import hashlib
import json
import re
from pathlib import Path, PurePosixPath
import sys
import tarfile

parser=argparse.ArgumentParser()
parser.add_argument('archive',type=Path)
parser.add_argument('--require-publisher-google',action='store_true')
parser.add_argument('--require-publisher',choices=('google','onedrive','dropbox'),action='append',default=[])
args=parser.parse_args()
sha=hashlib.sha256()
with args.archive.open('rb') as stream:
    while block:=stream.read(1024*1024):sha.update(block)
errors=[];publisher={'google':False,'onedrive':False,'dropbox':False}
required={'opencommander/opencommander','opencommander/LICENSE','opencommander/README.md','opencommander/THIRD-PARTY.md','opencommander/install-local.sh'}
with tarfile.open(args.archive,'r:gz') as archive:
    members=archive.getmembers();names={m.name for m in members}
    for member in members:
        path=PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0]!='opencommander':
            errors.append('Unsafe package path')
        if path.name in {'rclone.conf','transfers.sqlite3','transfers.sqlite3-wal','transfers.sqlite3-shm','keystore.properties'} or path.suffix in {'.jks','.p12','.p8'}:
            errors.append('Private runtime/signing data in package')
        if member.islnk() or member.issym():
            link=PurePosixPath(member.linkname)
            # Relative runtime library links may contain '..'; validate lexically.
            parts=list(path.parent.parts) if member.issym() else []
            if link.is_absolute():errors.append('Absolute package link');continue
            escaped=False
            for part in link.parts:
                if part=='..':
                    if parts:parts.pop()
                    else:escaped=True
                elif part!='.':parts.append(part)
            if escaped or not parts or parts[0]!='opencommander':errors.append('Escaping package link')
        provider=next((kind for kind in publisher if path.name==kind+'-oauth.json'),None)
        if provider:
            if member.size>16384 or not member.isfile():errors.append('Invalid publisher client');continue
            try:
                data=json.load(archive.extractfile(member))
                if provider=='google':
                    valid=(isinstance(data,dict) and set(data)=={'client_id','client_secret'} and
                           all(isinstance(data[k],str) and data[k] for k in data) and
                           bool(re.fullmatch(r'[A-Za-z0-9._-]+\.apps\.googleusercontent\.com',data['client_id'])) and
                           len(data['client_secret'])<=1024 and not any(ord(c)<32 for c in data['client_secret']))
                else:
                    pattern=r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}' if provider=='onedrive' else r'[A-Za-z0-9]{10,64}'
                    valid=(isinstance(data,dict) and set(data)=={'client_id','flow'} and data['flow']=='pkce' and
                           isinstance(data['client_id'],str) and bool(re.fullmatch(pattern,data['client_id'])))
            except (ValueError,TypeError):valid=False
            if not valid:errors.append('Invalid publisher client')
            if valid and member.name=='opencommander/_internal/opencommander/assets/'+provider+'-oauth.json':
                publisher[provider]=True
    for name in required-names:errors.append('Missing required distribution component: '+name)
    executable=archive.getmember('opencommander/opencommander') if 'opencommander/opencommander' in names else None
    if executable and not executable.mode&0o111:errors.append('Application not executable')
if args.require_publisher_google and not publisher['google']:errors.append('Publisher Google Desktop client missing; public Google sign-in not ready')
for kind in args.require_publisher:
    if not publisher[kind]:errors.append('Publisher '+kind+' application missing; registration not bundled')
print(json.dumps({'archive':args.archive.name,'sha256':sha.hexdigest(),'publisher_google_configured':publisher['google'],'publisher_clients':publisher,'errors':errors},indent=2))
raise SystemExit(bool(errors))
