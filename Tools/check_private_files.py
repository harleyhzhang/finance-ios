#!/usr/bin/env python3
"""Check tracked paths/content before publishing. Not a general secret scanner."""
import re,subprocess,pathlib,sys
root=pathlib.Path(__file__).resolve().parents[1]
r=subprocess.run(['git','ls-files','-z'],cwd=root,capture_output=True,text=True)
if r.returncode: sys.exit('Initialize Git before running the tracked-file check.')
bad=[]
for path in filter(None,r.stdout.split('\0')):
    p=root/path
    if re.search(r'(^|/)(private|previews|node_modules|build)/|\.(worth|finance)profile$|(^|/)\.env(\.|$)|Finance/snapshot\.json$|Config/Local\.xcconfig$',path) and path!='.env.example':bad.append(path)
    if p.is_file() and p.stat().st_size<2_000_000:
        text=p.read_text(errors='replace')
        if re.search(r'(?m)^-----BEGIN [A-Z ]*PRIVATE KEY-----$|"readToken"\s*:\s*"[A-Za-z0-9_-]{40,}"|"encryptionKey"\s*:\s*"[A-Za-z0-9+/]{43}="',text):bad.append(path)
if bad:sys.exit('Private material detected: '+', '.join(sorted(set(bad))))
print('Tracked-file privacy checks passed.')
