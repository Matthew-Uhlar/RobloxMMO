// Deterministic launch artwork from the game's original OBJ geometry/materials.
// Run: node art/generate-launch.cjs (Windows, Node + PowerShell; no packages).
const fs=require('fs'),path=require('path'),cp=require('child_process');
const root=__dirname,out=path.join(root,'launch');fs.mkdirSync(out,{recursive:true});
const cache={};
function obj(name){
 if(cache[name])return cache[name];
 const raw=fs.readFileSync(path.join(root,name+'.obj'),'utf8'),materials={};let mat;
 const mtl=raw.match(/^mtllib (.+)$/m)[1].trim();
 for(const line of fs.readFileSync(path.join(root,mtl),'utf8').split(/\r?\n/)){
  if(line.startsWith('newmtl '))mat=line.slice(7).trim();
  if(line.startsWith('Kd '))materials[mat]=line.slice(3).trim().split(/\s+/).map(x=>+x*255);
 }
 const vertices=[],faces=[];let current;
 for(const line of raw.split(/\r?\n/)){
  if(line.startsWith('v '))vertices.push(line.slice(2).trim().split(/\s+/).map(Number));
  if(line.startsWith('usemtl '))current=line.slice(7).trim();
  if(line.startsWith('f ')){const ids=line.slice(2).trim().split(/\s+/).map(x=>+x.split('/')[0]-1);for(let i=1;i<ids.length-1;i++)faces.push({ids:[ids[0],ids[i],ids[i+1]],color:materials[current]});}
 }
 return cache[name]={vertices,faces};
}
const hex=rgb=>'#'+rgb.map(x=>Math.max(0,Math.min(255,Math.round(x))).toString(16).padStart(2,'0')).join('');
function scene(width,height){
 const commands=[];const add=(type,data)=>commands.push({type,...data});
 const ellipse=(x,y,w,h,color)=>add('ellipse',{x,y,w,h,color});
 const polygon=(points,color)=>add('polygon',{points,color});
 const text=(value,x,y,size,color,font='Segoe UI',bold=true)=>add('text',{value,x,y,size,color,font,bold});
 const model=(name,x,y,scale,rotation=0,opacity=1)=>{
  const data=obj(name),ca=Math.cos(rotation),sa=Math.sin(rotation);
  const vertices=data.vertices.map(([a,b,c])=>[a*ca-c*sa,b,a*sa+c*ca]);
  const projected=vertices.map(([a,b,c])=>[x+(a*.866-c*.5)*scale,y+(-b*.89+(a*.5+c*.866)*.455)*scale,a*.445+b*.455+c*.771]);
  const faces=data.faces.map(f=>{
   const p=f.ids.map(i=>vertices[i]),u=p[1].map((v,i)=>v-p[0][i]),v=p[2].map((v,i)=>v-p[0][i]);
   const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],len=Math.hypot(...n)||1;
   const light=.7+.3*Math.max(0,(n[0]*-.45+n[1]*.85+n[2]*.3)/len);
   const color=f.color.map((v,i)=>(v*light)*opacity+([53,100,119][i])*(1-opacity));
   return {points:f.ids.map(i=>projected[i].slice(0,2)),depth:f.ids.reduce((s,i)=>s+projected[i][2],0)/3,color:hex(color)};
  });
  faces.sort((a,b)=>a.depth-b.depth).forEach(f=>polygon(f.points,f.color));
 };
 add('gradient',{top:'#102438',bottom:'#659C9D'});
 // Broad light source and layered cloud banks keep the mesh silhouette legible.
 for(let ring=20;ring>=1;ring--){const radius=height*(.23+ring*.025);ellipse(width*.87-radius,height*.12-radius,radius*2,radius*2,'#03C4E6D5');}
 for(let i=0;i<18;i++){
  const x=(i*179+33)%width,y=height*(.36+(i%4)*.15),w=width*(.12+(i%3)*.04);
  ellipse(x-w*.5,y,w,height*.05,'#128FE6E0');
 }
 for(let i=0;i<33;i++){
  const x=(i*137+71)%width,y=(i*43+27)%(height*.57);
  ellipse(x,y,i%5===0?3:1.4,i%5===0?3:1.4,i%5===0?'#C7F4DB':'#739CB0');
 }
 if(width===height){
  // Island, crystal and friendly surveyor form a single strong app-icon shape.
  model('FloatingIslet',403,240,34,.2,.55);
  model('FloatingIslet',70,270,27,.1,.45);
  ellipse(135,433,245,18,'#34213C48');
  model('FloatingIslet',256,318,70,.32);
  model('AetherCrystal',232,270,27,.3);
  model('Surveyor',314,300,22,2.6);
  model('Lantern',164,308,16,0);
  model('Tidewing',374,199,7,.5);
  text('AETHER',100,30,64,'#F2F5DE','Georgia');
  text('ISLES',174,101,47,'#F4CD7C','Georgia');
  add('line',{x1:193,y1:169,x2:319,y2:169,color:'#E0BE79',width:2});
 }else{
  model('FloatingIslet',1150,290,43,.5,.55);
  model('FloatingIslet',700,230,31,-.4,.48);
  model('FloatingIslet',450,540,37,.8,.48);
  // Floating walkway, built from small warm-lit stepping stones.
  for(let i=0;i<7;i++){
   const x=970+i*25,y=402-i*13;
   polygon([[x,y],[x+19,y-4],[x+24,y+2],[x+5,y+7]],'#C9A268');
  }
  ellipse(676,655,475,25,'#29304753');
  model('FloatingIslet',900,455,105,.32);
  model('WindpineCrown',985,366,31,.2);
  model('AetherCrystal',856,378,37,.35);
  model('Surveyor',937,424,29,2.6);
  model('Lantern',770,443,22,.1);
  model('Tidewing',1050,222,12,.5);
  model('FloatingIslet',1240,650,39,.5,.7);
  text('AETHER',58,145,105,'#F2F5DE','Georgia');
  text('ISLES',60,260,105,'#F4CD7C','Georgia');
  add('line',{x1:66,y1:401,x2:352,y2:401,color:'#DDBB7A',width:3});
  text('FORGE YOUR HORIZON',65,429,26,'#E5F1DD');
  text('GATHER  /  CRAFT  /  EXPLORE',66,478,17,'#C5E1D3','Segoe UI',false);
  text('THE SKY IS ONLY THE BEGINNING',66,643,14,'#C5E1D3','Segoe UI',false);
 }
 return {width,height,commands};
}
for(const [name,w,h] of [['aether-isles-icon',512,512],['aether-isles-thumbnail',1280,720]]){
 const file=path.join(out,name+'.json');fs.writeFileSync(file,JSON.stringify(scene(w,h)));
 cp.execFileSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(root,'render-launch.ps1'),'-ScenePath',file,'-OutputPath',path.join(out,name+'.png')],{stdio:'inherit',windowsHide:true});
 fs.unlinkSync(file);
}
console.log('Rendered original OBJ launch assets to art/launch');
