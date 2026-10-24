from pathlib import Path
import json,sys,os,tempfile,fcntl
path=Path.home()/'.config/serpantinum/settings.json'
with (path.parent/'.mac-dock.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 data=json.loads(path.read_text());cfg=dict(data.get('macDock',{}))
 if sys.argv[1]=='pin':
  ident=sys.argv[2];pins=list(cfg.get('apps',[]));cfg['apps']=[x for x in pins if x!=ident] if ident in pins else pins+[ident]
 elif sys.argv[1]=='add':
  ident=sys.argv[2];pins=list(cfg.get('apps',[]))
  if ident not in pins:pins.append(ident)
  cfg['apps']=pins
 else:raise SystemExit('Unsupported operation')
 data['macDock']=cfg
 fd,name=tempfile.mkstemp(prefix='.mac-dock-',dir=path.parent)
 try:
  with os.fdopen(fd,'w') as f:json.dump(data,f,indent=2);f.write('\n')
  os.chmod(name,path.stat().st_mode & 0o777);os.replace(name,path)
 finally:
  if os.path.exists(name):os.unlink(name)
