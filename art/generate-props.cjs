// Original deterministic Aether Isles prop masters. Run from the project root.
const fs = require('fs');
const palette = ['C98D4F','F4CD7C','265860','39898E','9DF3D7','203748','C15557','FFD389','525570','9583B9'];
const shapes = {};
function shape(name, build) {
  const vertices=[], faces=[];
  const v = p => (vertices.push(p.map(x=>Math.round(x*10000)/10000)),vertices.length);
  const tri=(a,b,c,color)=>faces.push([a,b,c,color]);
  const quad=(a,b,c,d,color)=>{tri(a,b,c,color);tri(a,c,d,color)};
  function box(x,y,z,w,h,d,color,angle=0) {
    const ids=[];
    for(const [dx,dy,dz] of [[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]]) {
      const px=dx*w/2,py=dy*h/2;
      ids.push(v([x+px*Math.cos(angle)-py*Math.sin(angle),y+px*Math.sin(angle)+py*Math.cos(angle),z+dz*d/2]));
    }
    for(const face of [[0,3,2,1],[4,5,6,7],[0,1,5,4],[3,7,6,2],[0,4,7,3],[1,2,6,5]])quad(...face.map(i=>ids[i]),color);
  }
  function spindle(x,y,z,r,h,color,n=6,top=.2) {
    const bottom=[],upper=[];
    for(let i=0;i<n;i++){const a=i*2*Math.PI/n;bottom.push(v([x+Math.cos(a)*r,y-h/2,z+Math.sin(a)*r]));upper.push(v([x+Math.cos(a)*r*top,y+h/2,z+Math.sin(a)*r*top]));}
    for(let i=0;i<n;i++)quad(bottom[i],bottom[(i+1)%n],upper[(i+1)%n],upper[i],color);
    for(let i=1;i<n-1;i++){tri(bottom[0],bottom[i+1],bottom[i],color);tri(upper[0],upper[i],upper[i+1],color)}
  }
  function jewel(x,y,z,rx,ry,rz,color) {
    const ids=[[0,ry,0],[rx,0,0],[0,0,rz],[-rx,0,0],[0,0,-rz],[0,-ry,0]].map(p=>v([p[0]+x,p[1]+y,p[2]+z]));
    for(let i=1;i<=4;i++){const j=i===4?1:i+1;tri(ids[0],ids[i],ids[j],color);tri(ids[5],ids[j],ids[i],color)}
  }
  // Flat annular bands, authored in arbitrary orthogonal planes.
  function ring(radius,width,depth,color,segments=12,tilt=0,start=0,sweep=Math.PI*2,y=0) {
    const loops=[];
    for(let i=0;i<=segments;i++){
      const a=start+sweep*i/segments;
      loops.push([[-1,-1],[1,-1],[1,1],[-1,1]].map(([r,z])=>{
        const px=Math.cos(a)*(radius+r*width/2),py=Math.sin(a)*(radius+r*width/2),pz=z*depth/2;
        return v([px,py*Math.cos(tilt)-pz*Math.sin(tilt)+y,py*Math.sin(tilt)+pz*Math.cos(tilt)]);
      }));
    }
    for(let i=0;i<segments;i++)for(let side=0;side<4;side++)quad(loops[i][side],loops[i+1][side],loops[i+1][(side+1)%4],loops[i][(side+1)%4],color);
    if(sweep<Math.PI*2){quad(...loops[0].slice().reverse(),color);quad(...loops[segments],color)}
  }
  build({box,spindle,jewel,ring});shapes[name]={vertices,faces};
}
shape('AetherCrystal',({spindle,jewel})=>{spindle(0,-.8,0,1.6,.6,9,7,.8);jewel(0,.7,0,.65,1.8,.6,5);jewel(-.9,-.1,.2,.4,1,.45,4);jewel(.8,0,-.3,.4,1.15,.4,10)});
shape('WindpineCrown',({spindle})=>{spindle(0,-.5,0,.22,4.2,1,6,.75);for(let i=0;i<3;i++)spindle(0,.1+i*1.05,0,2.2-i*.5,2, i===1?4:3,7,.08)});
shape('Surveyor',({box,spindle,jewel})=>{spindle(0,-1.25,0,1.2,.5,6,8,.8);box(0,-.35,0,1.9,1.5,1.3,3);spindle(0,.7,0,1.25,1.05,2,6,.65);box(0,.8,-1.05,1.25,.3,.2,5);box(-1.25,-.25,0,.4,1.3,.5,1,-.28);box(1.25,-.25,0,.4,1.3,.5,1,.28);jewel(0,1.65,0,.25,.5,.25,5)});
shape('Pickaxe',({box,jewel})=>{box(0,-.2,0,.22,3.3,.25,1,-.18);box(0,1.1,0,2.3,.35,.32,2,.08);jewel(-1.2,.8,0,.3,.55,.2,4);jewel(1.2,.8,0,.3,.55,.2,4);box(.12,-1.25,0,.35,.55,.35,6,-.18)});
shape('Blade',({box,jewel})=>{jewel(0,.75,0,.43,1.8,.16,5);box(0,-.85,0,1.35,.2,.35,2);box(0,-1.4,0,.24,.9,.28,6);jewel(0,-1.95,0,.25,.25,.2,2)});
shape('Lantern',({box,spindle,jewel})=>{spindle(0,-.9,0,.75,.35,2,6,.85);spindle(0,.85,0,.85,.5,6,6,.4);jewel(0,0,0,.5,.8,.5,5);for(const x of [-.5,.5])for(const z of [-.4,.4])box(x,0,z,.1,1.6,.1,1);box(0,1.25,0,.18,.45,.18,2)});
shape('TimberBundle',({spindle,box})=>{spindle(-.4,0,0,.45,2.2,1,7,1);spindle(.45,0,.1,.45,2.5,2,7,1);spindle(0,0,-.65,.4,2,1,7,1);box(0,-.5,-.15,1.8,.16,1.5,3);box(0,.5,-.15,1.8,.16,1.5,3)});
shape('Moonbloom',({box,jewel,spindle})=>{spindle(0,-.8,0,.65,.35,1,6,.9);box(0,0,0,.12,1.8,.12,3);for(let i=0;i<5;i++){const a=i*Math.PI*2/5;jewel(Math.cos(a)*.5,.65,Math.sin(a)*.5,.4,.25,.4,i%2?10:5)}jewel(0,.85,0,.3,.3,.3,2);jewel(-.4,-.15,0,.6,.2,.25,4)});
shape('Fish',({jewel})=>{jewel(0,0,0,1.3,.65,.4,4);jewel(1.4,0,0,.5,.8,.15,2);jewel(-.8,.15,-.35,.14,.14,.1,6);jewel(0,.6,0,.4,.45,.12,5)});
shape('Tonic',({spindle,jewel})=>{spindle(0,-.15,0,.75,1.3,4,8,.8);spindle(0,.7,0,.35,.6,5,6,1);spindle(0,1.08,0,.4,.18,1,6,1);jewel(0,-.1,-.68,.3,.4,.06,2)});
shape('VaultChest',({box,spindle})=>{box(0,-.2,0,2.5,1.3,1.5,6);box(0,.55,0,2.6,.35,1.6,3);for(const x of [-.9,.9])box(x,0,-.81,.18,1.4,.12,2);box(0,.1,-.85,.45,.5,.12,2);spindle(0,.85,0,.25,.3,5,6,.3)});
shape('FloatingIslet',({spindle,box,jewel})=>{spindle(0,-.5,0,1.6,1.4,9,7,1.3);spindle(0,.3,0,2.1,.35,3,7,.95);jewel(0,-1.5,0,.8,1.2,.8,6);box(.55,.85,0,.8,.8,.8,2);spindle(-.7,1,0,.65,1.3,4,6,.05)});
shape('AlloyIngot',({box})=>{box(0,-.25,0,2.2,.5,1.1,1);box(0,.1,0,1.9,.3,.9,2);box(0,.3,0,.7,.08,.55,6)});
shape('AetherIngot',({box,jewel})=>{box(0,-.25,0,2.2,.5,1.1,3);box(0,.1,0,1.9,.3,.9,4);jewel(0,.35,0,.4,.2,.3,5)});
shape('Skyplate',({box,jewel})=>{box(0,.2,0,1.55,1.8,.65,3);box(-1.05,.65,0,.6,.7,.8,2,.2);box(1.05,.65,0,.6,.7,.8,2,-.2);box(0,-.8,0,1.6,.25,.8,1);jewel(0,.35,-.4,.45,.65,.18,5);box(0,1.2,0,.8,.2,.6,2)});
shape('ObservatoryArch',({box,ring,jewel})=>{
  for(const x of [-3.2,3.2]){box(x,-.2,0,1.15,4.4,1.4,6);box(x,-2.2,0,1.6,.4,1.7,1);box(x,.2,-.76,.25,3.3,.12,5);box(x,1.8,0,1.5,.4,1.6,2)}
  ring(3.2,.8,1.25,3,10,0,0,Math.PI,2);
  ring(3.2,.18,1.4,2,10,0,0,Math.PI,2);
  jewel(0,5.45,0,.65,.95,.45,5);
  for(const x of [-1.9,1.9])jewel(x,4.7,-.75,.24,.42,.16,2);
});
shape('EclipseAstrolabe',({ring,jewel,spindle})=>{
  ring(2.5,.28,.3,2,12,.4);ring(2.1,.22,.28,1,12,1.3);
  jewel(0,0,0,.95,1.45,.95,5);jewel(0,0,0,1.3,.65,.65,10);
  for(let i=0;i<4;i++){const a=i*Math.PI/2;jewel(Math.cos(a)*2.65,Math.sin(a)*2.65,0,.28,.4,.28,8)}
  spindle(0,-2.7,0,1.1,.45,6,8,.8);
});
shape('ObservatorySentinel',({box,spindle,jewel})=>{
  for(const x of [-.65,.65]){box(x,-2,0,.85,1.3,1,6);box(x,-2.6,-.23,1,.3,1.45,1)}
  spindle(0,-.35,0,1.35,2.1,3,6,.75);box(0,-1.15,0,2.5,.28,1.5,2);
  jewel(0,0,-1.05,.55,.85,.22,5);
  for(const x of [-1.6,1.6]){box(x,.45,0,.75,1,1.4,2,x*.12);box(x,-.65,0,.6,1.3,.8,3,x*.1);jewel(x,-1.4,0,.5,.5,.5,1)}
  box(0,1.35,0,1.45,1.15,1.1,6);box(0,1.45,-.61,1.1,.22,.14,5);
  jewel(0,2.15,0,.32,.7,.35,2);for(const x of [-.9,.9])jewel(x,1.9,0,.28,.5,.3,1);
});
const luaTable = x => Array.isArray(x)?'{'+x.map(luaTable).join(',')+'}':typeof x==='object'?'{'+Object.entries(x).map(([k,v])=>k+'='+luaTable(v)).join(',')+'}':JSON.stringify(x);
const entries=Object.entries(shapes).map(([name,data])=>`shapes.${name}=${luaTable(data)}`).join('\n');
for(const [name,data] of Object.entries(shapes))fs.writeFileSync(`art/${name}.obj`, `# Original Aether Isles ${name}\nmtllib AetherPalette.mtl\n`+data.vertices.map(p=>'v '+p.join(' ')).join('\n')+'\n'+data.faces.map(f=>`usemtl Shade${f[3]}\nf ${f.slice(0,3).join(' ')}`).join('\n')+'\n');
fs.writeFileSync('art/AetherPalette.mtl',palette.map((hex,i)=>`newmtl Shade${i+1}\nKd ${[0,2,4].map(n=>parseInt(hex.slice(n,n+2),16)/255).join(' ')}`).join('\n'));
fs.writeFileSync('art/PropCatalog.lua','-- Generated by art/generate-props.cjs; shared original geometry.\nlocal palette='+luaTable(palette)+'\nlocal shapes={}\n'+entries+'\nreturn {palette=palette,shapes=shapes}\n');
let source=fs.readFileSync('mesh.client.lua','utf8');
source=source.replace(/-- BEGIN GENERATED PROPS[\s\S]*?-- END GENERATED PROPS\n?/,'');
source=source.replace('local function wedgeFace','-- BEGIN GENERATED PROPS\n'+entries+'\n-- END GENERATED PROPS\n\nlocal function wedgeFace');
fs.writeFileSync('mesh.client.lua',source);
console.log('Generated '+Object.keys(shapes).length+' original prop meshes and shared UI catalog.');
