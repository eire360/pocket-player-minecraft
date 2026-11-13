from pathlib import Path
import subprocess,zipfile,json
w=Path('work')
root=Path.home()/'Library/Application Support/minecraft'
game=root/'instances/Smooth Shaders 26.3'
src=w/'pocketmod/src'
classes=w/'pocketclasses'
classes.mkdir(exist_ok=True)
dep=w/'webdeps'
jars=[w/'mc-compile-view.jar',*root.joinpath('libraries').rglob('*.jar'),*dep.glob('*.jar')]
args=['-proc:none','--release','25','-encoding','UTF-8','-cp',':'.join(map(str,jars)),'-d',str(classes),*(str(p) for t in ('main','client') for p in (src/t/'java').rglob('*.java'))]
argfile=w/'pocketmod/javac.args'
argfile.write_text('\n'.join(json.dumps(a,ensure_ascii=False) for a in args))
jdk=next(root.glob('runtime/*/mac-os-arm64/*/jre.bundle/Contents/Home'))
subprocess.run([jdk/'bin/javac','@'+str(argfile)],check=True)
out=w/'pocketmod/pocketplayer-1.0.1+26.3.jar'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
 for base in (classes,src/'main/resources'):
  for p in sorted(base.rglob('*')):
   if p.is_file():z.write(p,p.relative_to(base).as_posix())
print(out)
