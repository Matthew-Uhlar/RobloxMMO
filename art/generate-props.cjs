// Original deterministic Aether Isles prop masters. Run from the project root:
//   node art/generate-props.cjs && node art/generate-import.cjs
// Writes art/<Shape>.obj, art/AetherPalette.mtl, art/PropCatalog.lua and the
// embedded copy inside mesh.client.lua. The import bundle must be regenerated
// afterwards so art/import stays in parity with every OBJ (the build verifies it).
const fs = require('fs');
// Palette indices are 1-based in Lua. 1-10 are the original world shades.
// 11 is the TINT slot: the UI (and tinted world props) recolour these faces with
// the item's AetherData colour; its stored value is a neutral silver so untinted
// renders still read as metal. 12 dark handle wood, 13 glint/porcelain, 14 leaf.
const palette = ['C98D4F','F4CD7C','265860','39898E','9DF3D7','203748','C15557','FFD389','525570','9583B9','D9DFE6','6E4A30','F4F8F8','6BAF5A'];
const TINT = 11, HANDLE = 12, GLINT = 13, LEAF = 14;
const ICON_TRIANGLE_BUDGET = 120;
const shapes = {};
const iconBudget = {};
function rotation([rx,ry,rz]) {
  // Applied as roll (Z), then pitch (X), then yaw (Y).
  const [cx,sx,cy,sy,cz,sz]=[Math.cos(rx),Math.sin(rx),Math.cos(ry),Math.sin(ry),Math.cos(rz),Math.sin(rz)];
  return p => {
    let [x,y,z]=p;
    [x,y]=[x*cz-y*sz,x*sz+y*cz];
    [y,z]=[y*cx-z*sx,y*sx+z*cx];
    [x,z]=[x*cy+z*sy,-x*sy+z*cy];
    return [x,y,z];
  };
}
function shape(name, build) {
  const vertices=[], faces=[];
  const stack=[];
  const v = p => {
    for(let i=stack.length-1;i>=0;i--)p=stack[i](p);
    return (vertices.push(p.map(x=>Math.round(x*10000)/10000)),vertices.length);
  };
  const tri=(a,b,c,color)=>faces.push([a,b,c,color]);
  const quad=(a,b,c,d,color)=>{tri(a,b,c,color);tri(a,c,d,color)};
  // Local frame for nested parts: rotate (radians) then translate.
  function group({pos=[0,0,0],rot=[0,0,0]},fn) {
    const r=rotation(rot);
    stack.push(p=>{const q=r(p);return [q[0]+pos[0],q[1]+pos[1],q[2]+pos[2]]});
    fn();stack.pop();
  }
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
  // Surface of revolution about local +Y. profile: [[radius,y],...] bottom to top;
  // radius 0 makes a pole. color may be a function (band, segment) -> shade.
  // jitter(level, segment) scales radii for hand-cut, irregular silhouettes.
  function lathe(profile,{n=8,sx=1,sz=1,phase=0,color=TINT,capStart=false,capEnd=false,capColor,jitter}={}) {
    const shade=typeof color==='function'?color:()=>color;
    const rings=profile.map(([r,y],level)=>r===0?v([0,y,0]):Array.from({length:n},(_,i)=>{
      const a=phase+i*2*Math.PI/n,k=jitter?jitter(level,i):1;
      return v([Math.cos(a)*r*sx*k,y,Math.sin(a)*r*sz*k]);
    }));
    for(let level=0;level<rings.length-1;level++){
      const lo=rings[level],hi=rings[level+1];
      for(let i=0;i<n;i++){
        const j=(i+1)%n,c=shade(level,i);
        if(Array.isArray(lo)&&Array.isArray(hi))quad(lo[i],lo[j],hi[j],hi[i],c);
        else if(Array.isArray(hi))tri(lo,hi[j],hi[i],c);
        else if(Array.isArray(lo))tri(lo[i],lo[j],hi,c);
      }
    }
    const first=rings[0],last=rings[rings.length-1];
    if(capStart&&Array.isArray(first))for(let i=1;i<n-1;i++)tri(first[0],first[i+1],first[i],capColor??shade(-1,i));
    if(capEnd&&Array.isArray(last))for(let i=1;i<n-1;i++)tri(last[0],last[i],last[i+1],capColor??shade(profile.length,i));
  }
  // Extruded outline in the local XY plane (front face toward -Z). The outline
  // must be star-shaped about its centroid; caps are fanned from that centre.
  function prism(points,depth,color,sideColor=color,z=0) {
    const cx=points.reduce((s,p)=>s+p[0],0)/points.length,cy=points.reduce((s,p)=>s+p[1],0)/points.length;
    const front=points.map(([x,y])=>v([x,y,z-depth/2])),back=points.map(([x,y])=>v([x,y,z+depth/2]));
    const f0=v([cx,cy,z-depth/2]),b0=v([cx,cy,z+depth/2]),m=points.length;
    for(let i=0;i<m;i++){
      const j=(i+1)%m;
      tri(f0,front[j],front[i],color);tri(b0,back[i],back[j],color);
      quad(front[i],front[j],back[j],back[i],sideColor);
    }
  }
  // Tapered bar: bottom w x d, top wt x dt, height h (12 triangles).
  function slab(x,y,z,w,d,wt,dt,h,color,topColor=color) {
    const ids=[[-w,-h,-d],[w,-h,-d],[wt,h,-dt],[-wt,h,-dt],[-w,-h,d],[w,-h,d],[wt,h,dt],[-wt,h,dt]].map(([px,py,pz])=>v([x+px/2,y+py/2,z+pz/2]));
    for(const [face,c] of [[[0,3,2,1],color],[[4,5,6,7],color],[[0,1,5,4],color],[[3,7,6,2],topColor],[[0,4,7,3],color],[[1,2,6,5],color]])quad(...face.map(i=>ids[i]),c);
  }
  build({box,spindle,jewel,ring,lathe,prism,slab,group});shapes[name]={vertices,faces};
}
// Deterministic pseudo-random jitter (no Math.random: output must be stable).
const hash=(a,b,seed)=>{
  let h=Math.imul(a+1,0x9E3779B1)^Math.imul(b+7,0x85EBCA6B)^Math.imul(seed+13,0xC2B2AE35);
  h=Math.imul(h^(h>>>15),0x2C1B3C6D);h=Math.imul(h^(h>>>12),0x297A2D39);h^=h>>>15;
  return (h>>>0)/4294967296;
};
const jitterOf=(seed,amount)=>(level,i)=>Math.round((1+(hash(level,i,seed)-.5)*2*amount)*1000)/1000;
// Item icons: the UI renders each triangle as two WedgeParts, so stay in budget.
function icon(name,build){shape(name,build);iconBudget[name]=shapes[name].faces.length}

// ---------------------------------------------------------------------------
// Original world props and legacy item icons (geometry unchanged).
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Depth item icons. Fronts face -Z (the UI camera looks from +X/+Y/-Z).
// TINT faces take the item's colour; trims, handles and glints stay fixed.
// ---------------------------------------------------------------------------
const PI=Math.PI;
icon('Sword',({lathe,box,jewel,group})=>group({rot:[0,-.3,-.62]},()=>{
  lathe([[.34,-.35],[.3,1.55],[0,2.45]],{n:4,sz:.22,capStart:true});
  box(0,.6,-.082,.07,1.7,.02,GLINT);
  box(0,-.42,0,1.2,.2,.36,2);
  for(const s of [-1,1])box(s*.68,-.33,0,.32,.18,.34,2,s*.4);
  jewel(0,-.42,-.2,.14,.14,.06,5);
  box(0,-.95,0,.2,.85,.22,HANDLE);
  jewel(0,-1.5,0,.22,.22,.22,2);
}));
icon('Helm',({lathe,box,group})=>group({rot:[0,-.45,0]},()=>{
  lathe([[1.0,-.55],[1.02,.1],[.92,.75],[.55,1.2],[0,1.35]],{n:8,phase:PI/8});
  lathe([[1.08,-.62],[1.08,-.36]],{n:8,phase:PI/8,color:2});
  box(0,.12,-.97,1.1,.18,.16,6);
  box(0,-.2,-.99,.2,.55,.12,6);
  box(0,1.15,.1,.16,.6,1.5,7);
}));
icon('Chestplate',({lathe,box,jewel,group})=>group({rot:[0,-.4,0]},()=>{
  lathe([[.85,-1.0],[1.0,-.2],[1.15,.55],[.95,1.0]],{n:6,sz:.6,capStart:true,capEnd:true});
  lathe([[.97,-.82],[.97,-.6]],{n:6,sz:.64,color:6});
  for(const s of [-1,1])group({pos:[s*1.0,.92,0],rot:[0,0,-s*.45]},()=>lathe([[.5,-.05],[.36,.24],[0,.36]],{n:6,sz:.9,color:2}));
  box(0,1.04,0,.8,.14,.5,2);
  jewel(0,.3,-.6,.18,.26,.07,5);
}));
icon('Greaves',({lathe,box,jewel,group})=>group({rot:[0,-.35,0]},()=>{
  box(0,.95,0,1.75,.32,.85,HANDLE);
  jewel(0,.95,-.45,.15,.13,.06,2);
  for(const s of [-1,1]){
    group({pos:[s*.45,0,0],rot:[0,0,s*.04]},()=>lathe([[.36,-1.15],[.3,-.85],[.42,.1],[.4,.85]],{n:6,sz:.85,capStart:true}));
    jewel(s*.45,-.05,-.33,.2,.24,.1,2);
  }
}));
icon('Boots',({box,jewel})=>{
  for(const [x,z] of [[-.5,.35],[.62,-.35]]){
    box(x,.3,z,.55,1.1,.6,TINT);
    box(x-.32,-.33,z,1.15,.45,.62,TINT);
    box(x-.3,-.62,z,1.3,.14,.7,6);
    box(x,.9,z,.66,.18,.7,2);
    jewel(x,.35,z-.31,.12,.12,.05,2);
  }
});
icon('ForgedPickaxe',({box,lathe,jewel,group})=>group({rot:[0,0,-.3]},()=>{
  box(0,-.2,0,.22,3.2,.24,HANDLE);
  box(0,-1.35,0,.3,.6,.3,1);
  jewel(0,-1.75,0,.2,.16,.2,2);
  box(0,1.25,0,.44,.44,.42,2);
  for(const s of [-1,1])group({pos:[s*.18,1.25,0],rot:[0,0,-s*(PI/2+.32)]},()=>lathe([[.21,0],[.15,.7],[0,1.35]],{n:4,sz:.75,phase:PI/4,capStart:true}));
  jewel(0,1.25,-.23,.12,.12,.05,5);
}));
icon('Hatchet',({box,prism,group})=>group({rot:[0,0,.22]},()=>{
  box(0,-.15,0,.22,3.0,.24,HANDLE);
  box(0,-1.25,0,.28,.6,.3,1);
  group({pos:[0,1.05,0]},()=>{
    prism([[.05,.3],[.45,.42],[.85,.82],[1.08,.2],[1.08,-.4],[.85,-.92],[.45,-.42],[.05,-.3]],.2,TINT);
    box(1.06,-.1,0,.08,.62,.22,GLINT);
    box(-.05,0,0,.42,.62,.34,2);
  });
}));
icon('Rod',({lathe,box,jewel,group})=>{
  const tilt=-.5,tip=[-2.6*Math.sin(tilt),2.6*Math.cos(tilt)];
  group({rot:[0,0,tilt]},()=>{
    lathe([[.14,-.95],[.05,2.6]],{n:5,capEnd:true});
    lathe([[.2,-1.75],[.18,-.95]],{n:6,color:HANDLE,capStart:true,capEnd:true});
    group({pos:[.26,-.7,0],rot:[PI/2,0,0]},()=>lathe([[.3,-.09],[.3,.09]],{n:8,color:2,capStart:true,capEnd:true}));
    jewel(.26,-.7,-.14,.07,.07,.07,GLINT);
  });
  box(tip[0],tip[1]-.75,0,.04,1.5,.04,GLINT);
  jewel(tip[0],tip[1]-1.6,0,.2,.24,.2,7);
  jewel(tip[0],tip[1]-1.33,0,.09,.12,.09,GLINT);
});
icon('Hoe',({box,jewel,group})=>group({rot:[0,-.35,.32]},()=>{
  box(0,-.1,0,.2,3.1,.22,HANDLE);
  box(0,-1.25,0,.26,.55,.28,1);
  jewel(0,-1.62,0,.18,.15,.18,2);
  box(-.05,1.42,0,.3,.3,.3,2);
  box(-.5,1.5,0,.8,.16,.2,2,.12);
  group({pos:[-.98,1.08,0],rot:[0,0,-.42]},()=>{box(0,0,0,.16,.9,.9,TINT);box(0,-.47,0,.18,.08,.92,GLINT)});
}));
icon('OreChunk',({lathe,group})=>{
  const vein=(level,i)=>((level*3+i*2+21)%7===0?TINT:level<0?6:9);
  lathe([[.95,-.75],[1.25,-.2],[1.08,.4],[.55,.82],[0,.98]],{n:6,phase:.3,capStart:true,color:vein,jitter:jitterOf(3,.14)});
  for(const [x,y,z,rx,rz,len,r] of [[-.45,.45,-.3,-.45,.45,.95,.28],[.45,.4,-.35,-.35,-.6,.8,.25],[.0,.7,.05,.05,-.08,1.15,.33],[.2,-.05,-.75,-1.15,.1,.75,.25]])
    group({pos:[x,y,z],rot:[rx,0,rz]},()=>lathe([[r,0],[r*1.05,len*.68],[0,len]],{n:5,phase:.4,capStart:true,color:(level,i)=>level===1&&i===1?GLINT:TINT}));
});
icon('Log',({lathe,group})=>group({rot:[PI/2,-1.05,0]},()=>{
  lathe([[.62,-1.2],[.66,1.2]],{n:9,capStart:true,capEnd:true,capColor:8,jitter:jitterOf(5,.06)});
  lathe([[.46,-1.21]],{n:9,capStart:true,color:1});
  lathe([[.27,-1.22]],{n:9,capStart:true,color:8});
  lathe([[.1,-1.23]],{n:9,capStart:true,color:1});
  group({pos:[.55,.35,0],rot:[0,0,-1.2]},()=>lathe([[.17,-.1],[.13,.35]],{n:5,capEnd:true,capColor:8}));
}));
icon('Finfish',({lathe,prism,jewel,group})=>{
  group({rot:[0,0,PI/2]},()=>lathe([[.14,-1.1],[.38,-.72],[.58,-.1],[.55,.55],[.32,1.12],[0,1.42]],{n:6,sz:.45,capStart:true}));
  prism([[1.0,.1],[1.8,.68],[1.58,0],[1.8,-.68],[1.0,-.1]],.08,TINT);
  prism([[-.35,.5],[.35,.48],[.12,.95],[-.2,.88]],.06,8);
  jewel(-.88,.16,-.19,.1,.1,.05,6);
  jewel(-.9,.19,-.235,.035,.035,.02,GLINT);
});
icon('CropSheaf',({lathe,jewel,group})=>{
  for(const [a,z,h] of [[-.42,.1,1.0],[-.2,-.15,1.15],[0,.05,1.3],[.22,-.12,1.12],[.42,.12,.98]])
    group({pos:[0,-.35,z],rot:[0,0,a]},()=>{
      lathe([[.07,-1.0],[.055,h]],{n:4,color:LEAF});
      jewel(0,h+.3,0,.15,.4,.15,TINT);
    });
  lathe([[.36,-.6],[.36,-.35]],{n:6,color:2,phase:.5});
  group({pos:[-.3,-.2,-.25],rot:[0,0,.9]},()=>jewel(0,.35,0,.1,.38,.05,LEAF));
});
icon('Ingot',({slab,box,group})=>{
  for(const z of [-.48,.48]){slab(0,-.3,z,2.0,.85,1.62,.58,.5,TINT);box(0,-.04,z-.1,1.2,.02,.1,GLINT)}
  group({pos:[0,.22,0],rot:[0,PI/2-.15,0]},()=>{slab(0,0,0,2.0,.85,1.62,.58,.5,TINT);box(0,.26,-.1,1.2,.02,.1,GLINT)});
});
icon('Potion',({lathe,jewel})=>{
  lathe([[0,-1.05],[.55,-.97],[.85,-.5],[.84,.12],[.5,.5],[.25,.64]],{n:7});
  lathe([[.24,.6],[.22,1.0]],{n:6,color:GLINT});
  lathe([[.33,.98],[.33,1.1]],{n:6,color:2,capStart:true});
  lathe([[.2,1.08],[.25,1.42]],{n:6,color:HANDLE,capEnd:true});
  jewel(-.33,-.2,-.74,.09,.26,.05,GLINT);
});
icon('Meal',({lathe,box,jewel,group})=>group({rot:[-.42,0,0]},()=>{
  lathe([[1.08,-.14],[1.45,.06]],{n:10,color:GLINT,capStart:true});
  lathe([[1.45,.06],[1.48,.1]],{n:10,color:2});
  group({pos:[-.05,-.1,.05],rot:[0,.45,0]},()=>{
    lathe([[0,-.02],[.62,.08],[.66,.28],[0,.44]],{n:6,sx:1.5,sz:.8});
    for(const x of [-.25,.25])box(x,.4,0,.09,.06,.66,HANDLE);
  });
  jewel(-.85,.06,-.5,.24,.06,.13,LEAF);
  jewel(.75,.06,-.62,.18,.08,.12,2);
}));
icon('Feast',({lathe,box,jewel,group})=>group({rot:[-.3,0,0]},()=>{
  lathe([[1.3,-.2],[1.62,-.04]],{n:10,color:2,capStart:true});
  lathe([[1.0,-.1],[.96,.32],[.62,.74],[0,.86]],{n:7,capStart:true,jitter:jitterOf(9,.05)});
  group({pos:[.55,.6,-.2],rot:[.5,0,-.7]},()=>{box(0,.35,0,.14,.7,.14,GLINT);jewel(-.07,.75,0,.14,.14,.14,GLINT);jewel(.07,.75,0,.14,.14,.14,GLINT)});
  jewel(-1.0,.0,-.75,.25,.08,.15,LEAF);
  jewel(.9,0,-.85,.2,.08,.14,LEAF);
}));
icon('Ring',({ring,box,jewel,group})=>group({rot:[1.2,-.5,0]},()=>{
  ring(.78,.22,.36,2,10);
  box(0,.92,0,.4,.18,.4,2);
  jewel(0,1.3,0,.46,.4,.46,TINT);
  jewel(-.12,1.43,-.25,.08,.09,.05,GLINT);
}));
icon('Charm',({prism,ring,jewel,group})=>group({rot:[0,-.5,0]},()=>{
  prism([[0,1.0],[.45,.68],[.64,.1],[.47,-.5],[0,-1.0],[-.47,-.5],[-.64,.1],[-.45,.68]],.22,TINT,2);
  jewel(0,.02,-.12,.24,.4,.07,2);
  jewel(-.27,.45,-.12,.06,.12,.03,GLINT);
  ring(.2,.08,.09,2,6,0,0,PI*2,1.2);
}));
icon('Amulet',({lathe,box,jewel,group})=>group({rot:[0,-.5,0]},()=>{
  for(const s of [-1,1])box(s*.5,.95,.05,.06,1.25,.06,2,-s*.42);
  box(0,.42,0,.22,.2,.2,2);
  group({pos:[0,-.2,0],rot:[-PI/2,0,0]},()=>lathe([[.62,-.08],[.62,.08]],{n:10,color:2,capStart:true,capEnd:true}));
  jewel(0,-.2,-.1,.38,.38,.16,TINT);
  for(const [x,y] of [[-.42,.2],[.42,.2],[-.42,-.6],[.42,-.6]])jewel(x*.85,y*.85-.05,-.1,.07,.07,.04,GLINT);
}));
icon('Circlet',({ring,jewel})=>{
  const t=1.25,r=.95;
  ring(r,.16,.3,2,9,t);
  for(const [a,big] of [[-PI/2,1],[-PI/2-.75,0],[-PI/2+.75,0]]){
    const x=Math.cos(a)*r,y=Math.sin(a)*r*Math.cos(t),z=Math.sin(a)*r*Math.sin(t);
    jewel(x,y+(big?.5:.36),z,.12,big?.38:.26,.08,2);
    jewel(x,y,z-.08,big?.22:.16,big?.22:.16,.09,TINT);
  }
});
icon('Seal',({lathe,prism,box,group})=>group({rot:[0,-.5,0]},()=>{
  group({rot:[-PI/2,0,0]},()=>lathe([[.95,-.1],[.9,.1]],{n:10,capStart:true,capEnd:true,jitter:jitterOf(11,.06)}));
  const star=[];
  for(let i=0;i<10;i++){const a=PI/2+i*PI/5,r=i%2?.24:.58;star.push([Math.cos(a)*r,Math.sin(a)*r])}
  prism(star,.08,2,2,-.13);
  for(const s of [-1,1])box(s*.32,-1.05,.12,.3,.75,.05,3,s*.3);
}));
icon('PetEgg',({lathe,jewel,group})=>{
  const profile=[[0,-1.0],[.55,-.86],[.8,-.38],[.78,.22],[.56,.78],[0,1.12]];
  lathe(profile,{n:8,phase:PI/8});
  lathe([[.5,-1.08],[.72,-.78]],{n:8,phase:PI/8,color:2,capStart:true});
  const radius=y=>{for(let i=0;i<profile.length-1;i++){const [r0,y0]=profile[i],[r1,y1]=profile[i+1];if(y>=y0&&y<=y1)return r0+(r1-r0)*(y-y0)/(y1-y0)}return 0};
  for(const [y,a,s,c] of [[.15,-.35,.2,GLINT],[-.45,.3,.16,2],[.55,.25,.13,GLINT],[-.1,.78,.12,2]])
    group({rot:[0,a,0]},()=>jewel(0,y,-radius(y)*.93,s,s*1.1,.05,c));
});
icon('DustPile',({lathe,jewel})=>{
  lathe([[1.2,-.45],[.8,-.1],[.3,.32],[0,.46]],{n:8,capStart:true,jitter:jitterOf(17,.12)});
  for(const [x,y,z,s,c] of [[.05,.85,-.15,.22,GLINT],[-.62,.35,-.55,.15,5],[.7,.15,-.5,.13,GLINT]]){
    jewel(x,y,z,s*.35,s*1.3,s*.2,c);jewel(x,y,z,s*1.3,s*.35,s*.2,c);
  }
  for(const [x,z] of [[-1.25,-.4],[1.1,-.7],[.3,-1.2]])jewel(x,-.38,z,.1,.08,.1,TINT);
});
icon('EssenceOrb',({lathe,jewel,group})=>{
  group({pos:[0,.3,0]},()=>lathe([[0,-.75],[.53,-.53],[.75,0],[.53,.53],[0,.75]],{n:8,phase:PI/8}));
  lathe([[.62,-.85],[.42,-.5]],{n:6,color:6,capStart:true});
  for(let i=0;i<3;i++){const a=-PI/2+i*2*PI/3;group({pos:[Math.cos(a)*.45,-.5,Math.sin(a)*.45],rot:[0,-a,-.35]},()=>lathe([[.08,0],[0,.7]],{n:3,color:2,capStart:true}))}
  jewel(-.25,.55,-.66,.08,.16,.04,GLINT);
  jewel(.95,.95,-.25,.07,.07,.07,5);
  jewel(-.9,-.05,-.35,.06,.06,.06,5);
});
icon('Feather',({prism,box,group})=>group({rot:[0,0,-.55]},()=>{
  prism([[0,1.65],[.36,1.15],[.5,.45],[.44,-.25],[.27,-.72],[.07,-.98],[-.2,-.75],[-.36,-.25],[-.22,.05],[-.44,.32],[-.42,.95],[-.24,1.35]],.05,TINT);
  box(0,-.05,0,.06,3.1,.08,GLINT);
  box(0,-1.42,0,.07,.36,.09,HANDLE);
}));
icon('HideRoll',({lathe,group})=>group({rot:[0,.35,-PI/2]},()=>{
  lathe([[.55,-1.1],[.55,1.1]],{n:8,capStart:true,capEnd:true,jitter:jitterOf(21,.05)});
  lathe([[.4,1.115]],{n:8,capEnd:true,color:6});
  lathe([[.33,1.13]],{n:8,capEnd:true});
  lathe([[.12,1.145]],{n:8,capEnd:true,color:6});
  for(const y of [-.62,.44])lathe([[.585,y],[.585,y+.18]],{n:8,color:1});
}));

// ---------------------------------------------------------------------------
// World polish: tinted crystal cluster that mesh.client.lua seats on ore nodes.
// ---------------------------------------------------------------------------
shape('OreCluster',({lathe,group})=>{
  for(const [x,z,rx,rz,len,r] of [[0,0,0,0,1.6,.3],[.42,.15,.15,-.5,1.1,.22],[-.4,.2,.2,.55,1.2,.24],[.1,-.38,-.55,-.15,1.0,.2],[-.15,.42,.5,.2,.85,.18]])
    group({pos:[x,0,z],rot:[rx,0,rz]},()=>lathe([[r,-.1],[r*1.12,len*.62],[0,len]],{n:5,phase:.3,capStart:true,color:(level,i)=>level===1&&i===0?GLINT:TINT}));
});

// ---------------------------------------------------------------------------
// Validation and output.
// ---------------------------------------------------------------------------
for(const [name,count] of Object.entries(iconBudget))
  if(count>ICON_TRIANGLE_BUDGET)throw new Error(`${name} has ${count} triangles; icon budget is ${ICON_TRIANGLE_BUDGET}`);
for(const [name,data] of Object.entries(shapes))for(const [a,b,c,shade] of data.faces){
  const [p,q,r]=[a,b,c].map(i=>data.vertices[i-1]);
  const u=q.map((x,k)=>x-p[k]),w=r.map((x,k)=>x-p[k]);
  const n=[u[1]*w[2]-u[2]*w[1],u[2]*w[0]-u[0]*w[2],u[0]*w[1]-u[1]*w[0]];
  if(Math.hypot(...n)<=1e-5)throw new Error(`${name} has a degenerate triangle`);
  if(!palette[shade-1])throw new Error(`${name} uses unknown shade ${shade}`);
}
const iconShapeLua = `
-- Item icon art: Catalog.iconShape(itemDef) -> shape name for an AetherData item.
-- Faces using Catalog.tintIndex are recoloured with the item's colour.
local Catalog={palette=palette,shapes=shapes,tintIndex=${TINT}}
local bespoke={
	Pickaxe="Pickaxe",ReinforcedPickaxe="Pickaxe",Blade="Blade",Stormblade="Blade",Skyplate="Skyplate",
	Tonic="Tonic",AlloyIngot="AlloyIngot",AetherIngot="AetherIngot",Fish="Fish",Moonbloom="Moonbloom",
	Aetherite="AetherCrystal",Shard="AetherCrystal",Stormglass="AetherCrystal",Timber="TimberBundle",
	ExpeditionRation="Meal",ArcaneDust="DustPile",VoidEssence="EssenceOrb",GolemCore="EssenceOrb",
	StarFragment="EssenceOrb",StormFeather="Feather",BeastHide="HideRoll",SpiderSilk="HideRoll",SlayerToken="Seal",
}
local slotShapes={helmet="Helm",chest="Chestplate",legs="Greaves",boots="Boots"}
local toolShapes={Pickaxe="ForgedPickaxe",Hatchet="Hatchet",Rod="Rod",Hoe="Hoe"}
local skillShapes={Mining="OreChunk",Woodcutting="Log",Fishing="Finfish",Farming="CropSheaf"}
local function has(id,...)
	for _,word in ipairs({...}) do if string.find(id,word,1,true) then return true end end
	return false
end
function Catalog.iconShape(def)
	if type(def)~="table" then return nil end
	local id=if type(def.id)=="string" then def.id else ""
	if bespoke[id] then return bespoke[id] end
	local kind=def.kind
	if kind=="weapon" then return "Sword"
	elseif kind=="armor" then return slotShapes[def.slot] or "Chestplate"
	elseif kind=="tool" then return toolShapes[def.toolKind] or "ForgedPickaxe"
	elseif kind=="resource" then return skillShapes[def.skill] or "OreChunk"
	elseif kind=="consumable" then
		if def.category=="potion" then return "Potion" elseif def.category=="buff" then return "Feast" end
		return if def.category=="food" or def.heal then "Meal" else "Potion"
	elseif kind=="accessory" then
		if has(id,"Ring","Band","Bracer","Cord") then return "Ring"
		elseif has(id,"Locket","Heartstone","Amulet","Pendant") then return "Amulet"
		elseif has(id,"Crown","Diadem","Circlet") then return "Circlet"
		elseif has(id,"Seal","Emblem","Sigil") then return "Seal" end
		return "Charm"
	elseif kind=="pet" then return "PetEgg"
	elseif kind=="material" then
		if string.sub(id,-5)=="Ingot" then return "Ingot"
		elseif has(id,"Dust","Powder") then return "DustPile"
		elseif has(id,"Essence","Core","Orb","Fragment") then return "EssenceOrb"
		elseif has(id,"Feather","Plume") then return "Feather"
		elseif has(id,"Hide","Silk","Pelt","Cloth") then return "HideRoll"
		elseif has(id,"Token","Seal","Emblem") then return "Seal"
		elseif has(id,"Shard","Glass","Crystal") then return "AetherCrystal" end
		return "DustPile"
	end
	return "EssenceOrb"
end
return Catalog
`;
const luaTable = x => Array.isArray(x)?'{'+x.map(luaTable).join(',')+'}':typeof x==='object'?'{'+Object.entries(x).map(([k,v])=>k+'='+luaTable(v)).join(',')+'}':JSON.stringify(x);
const entries=Object.entries(shapes).map(([name,data])=>`shapes.${name}=${luaTable(data)}`).join('\n');
for(const [name,data] of Object.entries(shapes))fs.writeFileSync(`art/${name}.obj`, `# Original Aether Isles ${name}\nmtllib AetherPalette.mtl\n`+data.vertices.map(p=>'v '+p.join(' ')).join('\n')+'\n'+data.faces.map(f=>`usemtl Shade${f[3]}\nf ${f.slice(0,3).join(' ')}`).join('\n')+'\n');
fs.writeFileSync('art/AetherPalette.mtl',palette.map((hex,i)=>`newmtl Shade${i+1}\nKd ${[0,2,4].map(n=>parseInt(hex.slice(n,n+2),16)/255).join(' ')}`).join('\n'));
fs.writeFileSync('art/PropCatalog.lua','-- Generated by art/generate-props.cjs; shared original geometry.\nlocal palette='+luaTable(palette)+'\nlocal shapes={}\n'+entries+'\n'+iconShapeLua);
let source=fs.readFileSync('mesh.client.lua','utf8');
source=source.replace(/^local palette = \{.*\}$/m,'local palette = {'+palette.map(hex=>`Color3.fromHex("${hex}")`).join(',')+'}');
source=source.replace(/^local TINT_INDEX = \d+$/m,'local TINT_INDEX = '+TINT);
source=source.replace(/-- BEGIN GENERATED PROPS[\s\S]*?-- END GENERATED PROPS\n*/,'');
source=source.replace('local function wedgeFace','-- BEGIN GENERATED PROPS\n'+entries+'\n-- END GENERATED PROPS\n\nlocal function wedgeFace');
fs.writeFileSync('mesh.client.lua',source);
console.log('Generated '+Object.keys(shapes).length+' original prop meshes and shared UI catalog.');
console.log('Icon triangles: '+Object.entries(iconBudget).map(([n,c])=>n+' '+c).join(', '));
