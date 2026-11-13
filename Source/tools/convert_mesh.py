from pathlib import Path
import json,math,struct,shutil
root=Path('work/pocketmod')
groups=[g for g in json.loads((root/'mesh/ipod-mesh.json').read_text()) if g['vertices'] and g['indices']]
def rect(x,y,w,h,r):
 out=[]
 for cx,cy,start in ((x+w-r,y+h-r,0),(x+r,y+h-r,90),(x+r,y+r,180),(x+w-r,y+r,270)):
  for i in range(32):
   a=math.radians(start+90*i/31)
   out.append((cx+r*math.cos(a),cy+r*math.sin(a)))
 return out
def group(name,color):
 g=dict(name=name,color=color,texture='',vertices=[],indices=[])
 groups.append(g)
 return g
def triangle(g,a,b,c):
 u=[b[i]-a[i] for i in range(3)];v=[c[i]-a[i] for i in range(3)]
 n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
 length=math.sqrt(sum(x*x for x in n))
 if length<1e-12:return
 n=[x/length for x in n]
 off=len(g['vertices'])
 g['vertices'].extend([list(p)+n+[0,0] for p in (a,b,c)])
 g['indices'].extend([off,off+1,off+2])
def strip(g,a,b,reverse=False):
 for i in range(len(a)):
  j=(i+1)%len(a)
  tris=((a[i],a[j],b[j]),(a[i],b[j],b[i]))
  for t in tris:triangle(g,*(reversed(t) if reverse else t))
# SceneKit's SCNShape surfaces need retessellation. Preserve its original outer
# contour, screen aperture, extrusion depth and .027 chamfer rather than boxing it.
if not any(g['name']=='curved polycarbonate faceplate with LCD aperture' for g in groups):
 g=group('original curved faceplate and aperture',[.79,.785,.771,1])
 outer=[]
 for z,inset in ((.005,.027),(.013,.008),(.032,0),(.076,0),(.095,.008),(.103,.027)):
  contour=[(x,y,z) for x,y in rect(-1.674+inset,-2.809+inset,3.348-2*inset,5.618-2*inset,.27-inset)]
  if outer:strip(g,outer[-1],contour)
  outer.append(contour)
 hole=[(x,y,.103) for x,y in rect(-1.201,.608,2.402,1.996,.068)]
 strip(g,outer[-1],hole,False)
 holeback=[(x,y,.005) for x,y,z in hole]
 strip(g,hole,holeback,True)
 strip(g,holeback,outer[0],True)
if not any(g['name']=='screen-frame' for g in groups):
 g=group('original recessed screen gasket',[.065,.07,.075,1])
 front=[(x,y,.118) for x,y in rect(-1.204,.605,2.408,2.002,.066)]
 for i in range(len(front)):triangle(g,(0,1.606,.118),front[i],front[(i+1)%len(front)])
assets=root/'src/main/resources/assets/pocketplayer'
(assets/'mesh').mkdir(exist_ok=True)
# Compact indexed mesh. Positions remain from original source; one unit maps to .16 blocks.
out=bytearray(struct.pack('>i',len(groups)))
for g in groups:
 tex=g['texture']
 texture='pocketplayer:textures/'+tex if tex else 'pocketplayer:textures/white.png'
 name=texture.encode();out+=struct.pack('>H',len(name))+name
 r,gg,b,a=g['color']
 out+=struct.pack('>i',len(g['vertices']))
 for v in g['vertices']:
  x,y,z,nx,ny,nz,u,t=v
  assert all(math.isfinite(n) for n in v)
  # Soft baked studio illumination; Minecraft still provides world light.
  normal=math.sqrt(nx*nx+ny*ny+nz*nz) or 1
  diffuse=max(0,(-.35*nx+.5*ny+.79*nz)/normal)
  shade=.67+.33*diffuse if not tex else 1
  color=(round(a*255)<<24)|(round(min(1,r*shade)*255)<<16)|(round(min(1,gg*shade)*255)<<8)|round(min(1,b*shade)*255)
  out+=struct.pack('>5fI',x*.16,y*.16,z*.16,u,1-t,color)
 inds=g['indices'];assert len(inds)%3==0 and max(inds)<len(g['vertices'])
 out+=struct.pack('>i',len(inds))+struct.pack('>'+str(len(inds))+'i',*inds)
 if tex:shutil.copy2(root/'mesh'/tex,assets/'textures'/tex)
(assets/'mesh/ipod.bin').write_bytes(out)
# Optional refresh: supply a preview from your own Pocket Player checkout.
import os
preview = os.environ.get('POCKET_PLAYER_PREVIEW')
if preview:
 shutil.copy2(Path(preview), assets/'textures/front.png')
elif not (assets/'textures/front.png').exists():
 raise SystemExit('Set POCKET_PLAYER_PREVIEW to your exported Preview.png')
# A generated constant color texture, not an edited visual asset.
import zlib
def pngchunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
(assets/'textures/white.png').write_bytes(b'\x89PNG\r\n\x1a\n'+pngchunk(b'IHDR',struct.pack('>2I5B',1,1,8,6,0,0,0))+pngchunk(b'IDAT',zlib.compress(b'\x00\xff\xff\xff\xff'))+pngchunk(b'IEND',b''))
print(len(groups),'mesh groups',sum(len(g['indices'])//3 for g in groups),'triangles',len(out),'bytes')
