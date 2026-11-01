
# Build optimized script.js — fast on laptop & mobile
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$lines = [System.Collections.Generic.List[string]]::new()

$lines.Add(@'
// ── State ────────────────────────────────────────────────────
let faceLandmarker=null,canvas,ctx,video=null,cameraReady=false,frameTime=0,frameCount=0,videoWidth=480,videoHeight=360;
let cachedLM=null,cachedBS=null; // cached detection result

// ── 35 Fast Filters ─────────────────────────────────────────
const FILTER_DEFS=[
  {id:"nose_clown",   label:"Clown Nose",      cat:"Nose"},
  {id:"nose_fire",    label:"Fire Nose",        cat:"Nose"},
  {id:"nose_rainbow", label:"Rainbow Nose",     cat:"Nose"},
  {id:"eyes_stars",   label:"Star Glasses",     cat:"Eyes"},
  {id:"eyes_sun",     label:"Sunglasses",       cat:"Eyes"},
  {id:"eyes_nerd",    label:"Nerd Glasses",     cat:"Eyes"},
  {id:"eyes_hearts",  label:"Heart Eyes",       cat:"Eyes"},
  {id:"eyes_laser",   label:"Laser Eyes",       cat:"Eyes"},
  {id:"eyes_dizzy",   label:"Dizzy Eyes",       cat:"Eyes"},
  {id:"eyes_money",   label:"Money Eyes",       cat:"Eyes"},
  {id:"eyes_3d",      label:"3D Glasses",       cat:"Eyes"},
  {id:"head_crown",   label:"Crown",            cat:"Hat"},
  {id:"head_party",   label:"Party Hat",        cat:"Hat"},
  {id:"head_wizard",  label:"Wizard Hat",       cat:"Hat"},
  {id:"head_santa",   label:"Santa Hat",        cat:"Hat"},
  {id:"head_tophat",  label:"Top Hat",          cat:"Hat"},
  {id:"head_halo",    label:"Angel Halo",       cat:"Hat"},
  {id:"head_devil",   label:"Devil Horns",      cat:"Hat"},
  {id:"ears_cat",     label:"Cat Ears",         cat:"Ears"},
  {id:"ears_dog",     label:"Dog Ears",         cat:"Ears"},
  {id:"ears_bunny",   label:"Bunny Ears",       cat:"Ears"},
  {id:"ears_flower",  label:"Flower Crown",     cat:"Ears"},
  {id:"face_moustache",label:"Moustache",       cat:"Face"},
  {id:"face_beard",   label:"Beard",            cat:"Face"},
  {id:"face_lips",    label:"Lipstick",         cat:"Face"},
  {id:"face_blush",   label:"Blush",            cat:"Face"},
  {id:"face_freckles",label:"Freckles",         cat:"Face"},
  {id:"face_fangs",   label:"Vampire Fangs",    cat:"Face"},
  {id:"face_eyepatch",label:"Pirate Eyepatch",  cat:"Face"},
  {id:"fx_bighead",   label:"Big Head",         cat:"Effects"},
  {id:"fx_tears",     label:"Tears",            cat:"Effects"},
  {id:"fx_rainbow",   label:"Rainbow Aura",     cat:"Effects"},
  {id:"fx_stars",     label:"Star Aura",        cat:"Effects"},
  {id:"fun_bow",      label:"Cute Bow",         cat:"Fun"},
  {id:"fun_monocle",  label:"Monocle",          cat:"Fun"},
];
const filters={};
FILTER_DEFS.forEach(f=>filters[f.id]=false);

// ── Particles ────────────────────────────────────────────────
const particles=[];
class Particle{
  constructor(x,y,t){this.x=x+(Math.random()-.5)*40;this.y=y;this.t=t;this.vx=(Math.random()-.5)*3;this.vy=-(Math.random()*2.5+1);this.life=1;this.sz=Math.random()*12+11;}
  update(){this.x+=this.vx;this.y+=this.vy;this.vy+=0.05;this.life-=0.02;}
  draw(c){c.globalAlpha=Math.max(0,this.life);c.font=this.sz+"px sans-serif";c.fillText(this.t,this.x,this.y);c.globalAlpha=1;}
}
function spawn(x,y,texts,n){for(let i=0;i<n;i++)particles.push(new Particle(x,y,texts[Math.floor(Math.random()*texts.length)]));}

const CAPTIONS=["FBI is reviewing this photo","Warning: Too attractive!","Mom I made it!","404 Normal face not found","Certified goofball","This face? ICONIC.","Munataha.exe stopped responding","AI says: exceptional specimen"];

// ── Camera — low-res for speed ───────────────────────────────
function initCamera(){
  video=document.createElement("video");
  video.setAttribute("playsinline","");video.muted=true;
  navigator.mediaDevices.getUserMedia({
    video:{facingMode:"user",width:{ideal:480},height:{ideal:360}}
  }).then(stream=>{
    video.srcObject=stream;video.play();
    video.onloadedmetadata=()=>{
      videoWidth=video.videoWidth||480;videoHeight=video.videoHeight||360;
      canvas=document.getElementById("outputCanvas");
      canvas.width=videoWidth;canvas.height=videoHeight;
      ctx=canvas.getContext("2d",{willReadFrequently:false});
      cameraReady=true;
      document.getElementById("loading").textContent="Loading filters...";
      requestAnimationFrame(drawLoop);
    };
  }).catch(e=>{document.getElementById("loading").textContent="Camera denied.";console.error(e);});
}

// ── Face model only — no hand model (too heavy) ──────────────
async function initFaceModel(){
  try{
    const v=await import("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.3");
    const fs=await v.FilesetResolver.forVisionTasks("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.3/wasm");
    faceLandmarker=await v.FaceLandmarker.createFromOptions(fs,{
      baseOptions:{
        modelAssetPath:"https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task",
        delegate:"GPU"
      },
      runningMode:"VIDEO",outputFaceBlendshapes:true,numFaces:1
    });
    document.getElementById("loading").style.display="none";
  }catch(e){
    console.error(e);
    document.getElementById("loading").textContent="Filters unavailable. Camera works!";
  }
}

// ── Helpers ──────────────────────────────────────────────────
function lx(lm,i){return videoWidth-lm[i].x*videoWidth;}
function ly(lm,i){return lm[i].y*videoHeight;}
function FW(lm){return Math.abs(lx(lm,234)-lx(lm,454));}
function FH(lm){return Math.abs(ly(lm,10)-ly(lm,175));}
function CX(lm){return(lx(lm,234)+lx(lm,454))/2;}
function eyeInfo(lm){
  const lEx=lx(lm,33),lEy=ly(lm,33),rEx=lx(lm,263),rEy=ly(lm,263);
  const dist=Math.hypot(rEx-lEx,rEy-lEy);
  return{lEx,lEy,rEx,rEy,dist,cx:(lEx+rEx)/2,cy:(lEy+rEy)/2};
}
function headTop(lm){
  const le=lx(lm,234),re=lx(lm,454),L=Math.min(le,re),R=Math.max(le,re);
  return{L,R,fw:R-L,cx:(L+R)/2,topY:ly(lm,10)};
}

// ── Draw loop — capped at 30fps, detection every 3rd frame ───
let lastFrameTS=0;
function drawLoop(){
  requestAnimationFrame(drawLoop);
  const now=performance.now();
  if(now-lastFrameTS < 33) return; // 30fps cap
  lastFrameTS=now;
  frameTime=now; frameCount++;

  // mirror video
  ctx.save();ctx.scale(-1,1);ctx.translate(-videoWidth,0);
  ctx.drawImage(video,0,0,videoWidth,videoHeight);ctx.restore();

  // run detection every 3rd frame only
  if(faceLandmarker&&video.readyState>=2&&frameCount%3===0){
    try{
      const r=faceLandmarker.detectForVideo(video,frameTime);
      if(r&&r.faceLandmarks.length>0){cachedLM=r.faceLandmarks[0];cachedBS=r.faceBlendshapes?.[0];}
      else{cachedLM=null;cachedBS=null;}
    }catch(e){}
  }

  const lm=cachedLM,bs=cachedBS;
  if(lm){
    if(filters.fx_bighead)drawBigHead();
    if(filters.ears_cat)drawCatEars(lm);
    if(filters.ears_dog)drawDogEars(lm);
    if(filters.ears_bunny)drawBunnyEars(lm);
    if(filters.ears_flower)drawFlowerCrown(lm);
    if(filters.head_crown)drawCrown(lm);
    if(filters.head_party)drawPartyHat(lm);
    if(filters.head_wizard)drawWizardHat(lm);
    if(filters.head_santa)drawSantaHat(lm);
    if(filters.head_tophat)drawTopHat(lm);
    if(filters.head_halo)drawHalo(lm);
    if(filters.head_devil)drawDevilHorns(lm);
    if(filters.face_blush)drawBlush(lm);
    if(filters.face_freckles)drawFreckles(lm);
    if(filters.face_beard)drawBeard(lm);
    if(filters.face_eyepatch)drawEyepatch(lm);
    if(filters.face_fangs)drawFangs(lm);
    if(filters.face_lips)drawLips(lm);
    if(filters.face_moustache)drawMoustache(lm);
    if(filters.fun_bow)drawBow(lm);
    if(filters.fun_monocle)drawMonocle(lm);
    if(filters.nose_clown)drawClownNose(lm);
    if(filters.nose_fire)drawFireNose(lm);
    if(filters.nose_rainbow)drawRainbowNose(lm);
    if(filters.eyes_stars)drawStarGlasses(lm);
    if(filters.eyes_sun)drawSunglasses(lm);
    if(filters.eyes_nerd)drawNerdGlasses(lm);
    if(filters.eyes_hearts)drawHeartEyes(lm);
    if(filters.eyes_laser)drawLaserEyes(lm);
    if(filters.eyes_dizzy)drawDizzyEyes(lm);
    if(filters.eyes_money)drawMoneyEyes(lm);
    if(filters.eyes_3d)draw3DGlasses(lm);
    if(filters.fx_tears)drawTears(lm);
    if(filters.fx_rainbow)drawRainbowAura(lm);
    if(filters.fx_stars)drawStarAura(lm);
    if(bs)handleExpressions(bs,lm);
  }

  // particles
  for(let i=particles.length-1;i>=0;i--){
    particles[i].update();particles[i].draw(ctx);
    if(particles[i].life<=0)particles.splice(i,1);
  }
}
'@)

$lines.Add(@'

// NOSE
function drawClownNose(lm){const x=lx(lm,1),y=ly(lm,1),r=Math.max(FW(lm)*.08,10);const g=ctx.createRadialGradient(x,y,r*.2,x,y,r);g.addColorStop(0,"#ff9999");g.addColorStop(1,"#cc0000");ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);ctx.fillStyle=g;ctx.fill();ctx.beginPath();ctx.arc(x-r*.3,y-r*.3,r*.25,0,Math.PI*2);ctx.fillStyle="rgba(255,255,255,.6)";ctx.fill();}
function drawFireNose(lm){const x=lx(lm,1),y=ly(lm,1),fw=FW(lm),t=frameTime/120;for(let i=0;i<3;i++){const ox=(i-1)*fw*.04,h=fw*.16*(0.8+Math.sin(t+i)*.2);const g=ctx.createLinearGradient(x+ox,y,x+ox,y-h);g.addColorStop(0,"#ff4400");g.addColorStop(.5,"#ff8800");g.addColorStop(1,"rgba(255,200,0,0)");ctx.beginPath();ctx.moveTo(x+ox-fw*.025,y);ctx.quadraticCurveTo(x+ox+fw*.03*Math.sin(t+i),y-h*.5,x+ox,y-h);ctx.quadraticCurveTo(x+ox-fw*.03*Math.sin(t+i),y-h*.5,x+ox+fw*.025,y);ctx.fillStyle=g;ctx.fill();}ctx.fillStyle="rgba(80,0,0,.7)";ctx.beginPath();ctx.ellipse(x,y,fw*.065,fw*.045,0,0,Math.PI*2);ctx.fill();}
function drawRainbowNose(lm){const x=lx(lm,1),y=ly(lm,1),r=Math.max(FW(lm)*.09,12);["#f00","#f80","#ff0","#0f0","#08f","#80f"].forEach((c,i)=>{ctx.beginPath();ctx.arc(x,y,r-i*2,0,Math.PI*2);ctx.lineWidth=2.5;ctx.strokeStyle=c;ctx.stroke();});ctx.beginPath();ctx.arc(x,y,r*.22,0,Math.PI*2);ctx.fillStyle="#fff";ctx.fill();}

// EYES
function drawStarGlasses(lm){const e=eyeInfo(lm),r=e.dist*.55;ctx.lineWidth=3.5;ctx.strokeStyle="#ff69b4";ctx.beginPath();ctx.arc(e.cx-e.dist/2,e.cy,r/1.5,0,Math.PI*2);ctx.stroke();ctx.beginPath();ctx.arc(e.cx+e.dist/2,e.cy,r/1.5,0,Math.PI*2);ctx.stroke();ctx.beginPath();ctx.moveTo(e.cx-e.dist/2+r/1.5,e.cy);ctx.lineTo(e.cx+e.dist/2-r/1.5,e.cy);ctx.stroke();ctx.font=(r*.9)+"px serif";ctx.textAlign="center";ctx.textBaseline="middle";ctx.fillStyle="#fff";ctx.fillText("*",e.cx-e.dist/2,e.cy);ctx.fillText("*",e.cx+e.dist/2,e.cy);}
function drawSunglasses(lm){const e=eyeInfo(lm),r=e.dist*.6;ctx.fillStyle="rgba(0,0,0,.82)";ctx.beginPath();ctx.ellipse(e.cx-e.dist/2,e.cy,r/1.4,r/2,0,0,Math.PI*2);ctx.fill();ctx.beginPath();ctx.ellipse(e.cx+e.dist/2,e.cy,r/1.4,r/2,0,0,Math.PI*2);ctx.fill();ctx.lineWidth=3.5;ctx.strokeStyle="#111";ctx.beginPath();ctx.ellipse(e.cx-e.dist/2,e.cy,r/1.4,r/2,0,0,Math.PI*2);ctx.stroke();ctx.beginPath();ctx.ellipse(e.cx+e.dist/2,e.cy,r/1.4,r/2,0,0,Math.PI*2);ctx.stroke();ctx.beginPath();ctx.moveTo(e.cx-e.dist/2+r/1.4,e.cy);ctx.lineTo(e.cx+e.dist/2-r/1.4,e.cy);ctx.stroke();ctx.fillStyle="rgba(255,255,255,.2)";ctx.beginPath();ctx.ellipse(e.cx-e.dist/2-r*.1,e.cy-r*.1,r/4,r/8,-0.3,0,Math.PI*2);ctx.fill();ctx.beginPath();ctx.ellipse(e.cx+e.dist/2-r*.1,e.cy-r*.1,r/4,r/8,-0.3,0,Math.PI*2);ctx.fill();}
function drawNerdGlasses(lm){const e=eyeInfo(lm),r=e.dist*.52,rx=r/1.4,ry=r/2.2;ctx.lineWidth=5;ctx.strokeStyle="#222";ctx.strokeRect(e.cx-e.dist/2-rx,e.cy-ry,rx*2,ry*2);ctx.strokeRect(e.cx+e.dist/2-rx,e.cy-ry,rx*2,ry*2);ctx.beginPath();ctx.moveTo(e.cx-e.dist/2+rx,e.cy);ctx.lineTo(e.cx+e.dist/2-rx,e.cy);ctx.stroke();ctx.fillStyle="#fff";ctx.fillRect(e.cx-4,e.cy-3,8,6);ctx.strokeStyle="#aaa";ctx.lineWidth=1;ctx.strokeRect(e.cx-4,e.cy-3,8,6);}
function drawHeartEyes(lm){const e=eyeInfo(lm),s=e.dist*.6;[[e.cx-e.dist/2,e.cy],[e.cx+e.dist/2,e.cy]].forEach(([px,py])=>{ctx.save();ctx.translate(px,py);ctx.font=s+"px serif";ctx.textAlign="center";ctx.textBaseline="middle";ctx.fillStyle="#ff1744";ctx.fillText("<3",0,0);ctx.restore();});}
function drawLaserEyes(lm){const e=eyeInfo(lm);[[e.lEx,e.lEy],[e.rEx,e.rEy]].forEach(([ex,ey])=>{const g=ctx.createRadialGradient(ex,ey,2,ex,ey,18);g.addColorStop(0,"rgba(255,0,0,1)");g.addColorStop(1,"rgba(255,0,0,0)");ctx.beginPath();ctx.arc(ex,ey,18,0,Math.PI*2);ctx.fillStyle=g;ctx.fill();const g2=ctx.createLinearGradient(ex,ey,ex,0);g2.addColorStop(0,"rgba(255,40,0,.9)");g2.addColorStop(1,"rgba(255,0,0,0)");ctx.fillStyle=g2;ctx.beginPath();ctx.moveTo(ex-4,ey);ctx.lineTo(ex+4,ey);ctx.lineTo(ex+2,0);ctx.lineTo(ex-2,0);ctx.fill();});}
function drawDizzyEyes(lm){const e=eyeInfo(lm),t=frameTime/250,s=e.dist*.5;[[e.cx-e.dist/2,e.cy],[e.cx+e.dist/2,e.cy]].forEach(([px,py])=>{ctx.save();ctx.translate(px,py);ctx.rotate(t);ctx.font=s+"px serif";ctx.textAlign="center";ctx.textBaseline="middle";ctx.fillText("X_X",0,0);ctx.restore();});}
function drawMoneyEyes(lm){const e=eyeInfo(lm),s=e.dist*.65;[[e.cx-e.dist/2,e.cy],[e.cx+e.dist/2,e.cy]].forEach(([px,py])=>{ctx.save();ctx.translate(px,py);ctx.font="bold "+s+"px Impact,sans-serif";ctx.textAlign="center";ctx.textBaseline="middle";ctx.fillStyle="#2ecc71";ctx.fillText("$",0,0);ctx.strokeStyle="#145a32";ctx.lineWidth=2;ctx.strokeText("$",0,0);ctx.restore();});}
function draw3DGlasses(lm){const e=eyeInfo(lm),r=e.dist*.58,rx=r/1.3,ry=r/2;ctx.fillStyle="rgba(255,0,0,.55)";ctx.beginPath();ctx.ellipse(e.cx-e.dist/2,e.cy,rx,ry,0,0,Math.PI*2);ctx.fill();ctx.fillStyle="rgba(0,80,255,.55)";ctx.beginPath();ctx.ellipse(e.cx+e.dist/2,e.cy,rx,ry,0,0,Math.PI*2);ctx.fill();ctx.lineWidth=3.5;ctx.strokeStyle="#111";ctx.beginPath();ctx.ellipse(e.cx-e.dist/2,e.cy,rx,ry,0,0,Math.PI*2);ctx.stroke();ctx.beginPath();ctx.ellipse(e.cx+e.dist/2,e.cy,rx,ry,0,0,Math.PI*2);ctx.stroke();ctx.beginPath();ctx.moveTo(e.cx-e.dist/2+rx,e.cy);ctx.lineTo(e.cx+e.dist/2-rx,e.cy);ctx.stroke();}
'@)

$lines.Add(@'

// HATS
function drawCrown(lm){const h=headTop(lm),ch=h.fw*.4,ty=h.topY-ch*.15;ctx.fillStyle="#FFD700";ctx.beginPath();ctx.moveTo(h.L,ty);ctx.lineTo(h.L,ty-ch*.65);ctx.lineTo(h.L+h.fw*.22,ty-ch*.3);ctx.lineTo(h.cx,ty-ch);ctx.lineTo(h.R-h.fw*.22,ty-ch*.3);ctx.lineTo(h.R,ty-ch*.65);ctx.lineTo(h.R,ty);ctx.closePath();ctx.fill();ctx.strokeStyle="#B8860B";ctx.lineWidth=2.5;ctx.stroke();[{x:h.L+h.fw*.15,y:ty-ch*.12,c:"#f33"},{x:h.cx,y:ty-ch*.3,c:"#33f"},{x:h.R-h.fw*.15,y:ty-ch*.12,c:"#3c3"}].forEach(g=>{ctx.beginPath();ctx.arc(g.x,g.y,h.fw*.04,0,Math.PI*2);ctx.fillStyle=g.c;ctx.fill();});}
function drawPartyHat(lm){const h=headTop(lm),hh=h.fw*.55,bw=h.fw*.4;ctx.fillStyle="#ff4fae";ctx.beginPath();ctx.moveTo(h.cx-bw/2,h.topY);ctx.lineTo(h.cx+bw/2,h.topY);ctx.lineTo(h.cx,h.topY-hh);ctx.closePath();ctx.fill();["#ffe000","#00ddff","#ff6600"].forEach((c,i)=>{const t=(i+1)/4;ctx.strokeStyle=c;ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(h.cx-bw/2*t,h.topY-hh*t);ctx.lineTo(h.cx+bw/2*t,h.topY-hh*t);ctx.stroke();});ctx.beginPath();ctx.arc(h.cx,h.topY-hh,h.fw*.05,0,Math.PI*2);ctx.fillStyle="#fff";ctx.fill();}
function drawWizardHat(lm){const h=headTop(lm),hh=h.fw*.7,bw=h.fw*.45;ctx.fillStyle="#1a0033";ctx.beginPath();ctx.moveTo(h.cx-bw/2,h.topY);ctx.lineTo(h.cx+bw/2,h.topY);ctx.lineTo(h.cx,h.topY-hh);ctx.closePath();ctx.fill();ctx.fillStyle="#2a0044";ctx.beginPath();ctx.ellipse(h.cx,h.topY,bw*.65,h.fw*.07,0,0,Math.PI*2);ctx.fill();ctx.fillStyle="#ffd700";ctx.font=(h.fw*.12)+"px serif";ctx.textAlign="center";ctx.fillText("*",h.cx-bw*.2,h.topY-hh*.4);ctx.fillText("*",h.cx+bw*.15,h.topY-hh*.6);}
function drawSantaHat(lm){const h=headTop(lm),hh=h.fw*.55,bw=h.fw*.5;ctx.fillStyle="#cc0000";ctx.beginPath();ctx.moveTo(h.cx-bw/2,h.topY);ctx.quadraticCurveTo(h.cx+bw*.2,h.topY-hh*.5,h.cx+bw*.15,h.topY-hh);ctx.lineTo(h.cx+bw*.3,h.topY);ctx.closePath();ctx.fill();ctx.fillStyle="#fff";ctx.beginPath();ctx.ellipse(h.cx,h.topY,bw*.55,h.fw*.08,0,0,Math.PI*2);ctx.fill();ctx.beginPath();ctx.arc(h.cx+bw*.15,h.topY-hh,h.fw*.07,0,Math.PI*2);ctx.fill();}
function drawTopHat(lm){const h=headTop(lm),hh=h.fw*.5,bw=h.fw*.55,bd=h.fw*.38;ctx.fillStyle="#111";ctx.fillRect(h.cx-bd/2,h.topY-hh,bd,hh);ctx.beginPath();ctx.ellipse(h.cx,h.topY,bw/2,h.fw*.07,0,0,Math.PI*2);ctx.fill();ctx.strokeStyle="#8B6914";ctx.lineWidth=h.fw*.03;ctx.beginPath();ctx.moveTo(h.cx-bd/2,h.topY-hh*.2);ctx.lineTo(h.cx+bd/2,h.topY-hh*.2);ctx.stroke();}
function drawHalo(lm){const h=headTop(lm);ctx.save();ctx.translate(h.cx,h.topY-h.fw*.15);ctx.scale(1,.28);ctx.beginPath();ctx.arc(0,0,h.fw*.32,0,Math.PI*2);ctx.strokeStyle="rgba(255,220,0,.9)";ctx.lineWidth=h.fw*.07;ctx.stroke();ctx.restore();}
function drawDevilHorns(lm){const h=headTop(lm),hh=h.fw*.35;[h.L+h.fw*.15,h.R-h.fw*.15].forEach(hx=>{ctx.fillStyle="#cc0000";ctx.beginPath();ctx.moveTo(hx-h.fw*.1,h.topY);ctx.lineTo(hx+h.fw*.1,h.topY);ctx.lineTo(hx,h.topY-hh);ctx.closePath();ctx.fill();});}

// EARS
function drawCatEars(lm){const h=headTop(lm),eh=h.fw*.4,ew=h.fw*.18;ctx.fillStyle="#ffb6c1";ctx.beginPath();ctx.moveTo(h.L+h.fw*.15,h.topY);ctx.lineTo(h.L+h.fw*.05,h.topY-eh);ctx.lineTo(h.L+ew+h.fw*.15,h.topY);ctx.closePath();ctx.fill();ctx.fillStyle="#ff69b4";ctx.beginPath();ctx.moveTo(h.L+h.fw*.14,h.topY-1);ctx.lineTo(h.L+h.fw*.08,h.topY-eh*.75);ctx.lineTo(h.L+ew*.6+h.fw*.14,h.topY-1);ctx.closePath();ctx.fill();ctx.fillStyle="#ffb6c1";ctx.beginPath();ctx.moveTo(h.R-h.fw*.15,h.topY);ctx.lineTo(h.R-h.fw*.05,h.topY-eh);ctx.lineTo(h.R-ew-h.fw*.15,h.topY);ctx.closePath();ctx.fill();ctx.fillStyle="#ff69b4";ctx.beginPath();ctx.moveTo(h.R-h.fw*.14,h.topY-1);ctx.lineTo(h.R-h.fw*.08,h.topY-eh*.75);ctx.lineTo(h.R-ew*.6-h.fw*.14,h.topY-1);ctx.closePath();ctx.fill();}
function drawDogEars(lm){const h=headTop(lm),eh=h.fw*.45;ctx.fillStyle="#8B4513";ctx.beginPath();ctx.moveTo(h.L+h.fw*.1,h.topY);ctx.bezierCurveTo(h.L-h.fw*.05,h.topY+eh*.3,h.L-h.fw*.1,h.topY+eh*.8,h.L+h.fw*.05,h.topY+eh);ctx.bezierCurveTo(h.L+h.fw*.2,h.topY+eh*.8,h.L+h.fw*.2,h.topY+eh*.3,h.L+h.fw*.1,h.topY);ctx.closePath();ctx.fill();ctx.fillStyle="#8B4513";ctx.beginPath();ctx.moveTo(h.R-h.fw*.1,h.topY);ctx.bezierCurveTo(h.R+h.fw*.05,h.topY+eh*.3,h.R+h.fw*.1,h.topY+eh*.8,h.R-h.fw*.05,h.topY+eh);ctx.bezierCurveTo(h.R-h.fw*.2,h.topY+eh*.8,h.R-h.fw*.2,h.topY+eh*.3,h.R-h.fw*.1,h.topY);ctx.closePath();ctx.fill();}
function drawBunnyEars(lm){const h=headTop(lm),eh=h.fw*.75;ctx.fillStyle="#f0f0f0";ctx.beginPath();ctx.ellipse(h.cx-h.fw*.2,h.topY-eh/2,h.fw*.09,eh/2,-.15,0,Math.PI*2);ctx.fill();ctx.beginPath();ctx.ellipse(h.cx+h.fw*.2,h.topY-eh/2,h.fw*.09,eh/2,.15,0,Math.PI*2);ctx.fill();ctx.fillStyle="#ffb6c1";ctx.beginPath();ctx.ellipse(h.cx-h.fw*.2,h.topY-eh/2,h.fw*.045,eh*.38,-.15,0,Math.PI*2);ctx.fill();ctx.beginPath();ctx.ellipse(h.cx+h.fw*.2,h.topY-eh/2,h.fw*.045,eh*.38,.15,0,Math.PI*2);ctx.fill();}
function drawFlowerCrown(lm){const h=headTop(lm),cs=["#f44","#f84","#ff0","#4c4","#48f","#a4f","#f4a"];for(let i=0;i<7;i++){const t=i/6,x=h.L+h.fw*t,y=h.topY-h.fw*.05*(1-Math.abs(t-.5)*2),r=h.fw*.06;ctx.fillStyle=cs[i%cs.length];for(let p=0;p<5;p++){const a=p*(Math.PI*2/5);ctx.beginPath();ctx.arc(x+Math.cos(a)*r*.8,y+Math.sin(a)*r*.8,r*.5,0,Math.PI*2);ctx.fill();}ctx.fillStyle="rgba(255,255,100,.8)";ctx.beginPath();ctx.arc(x,y,r*.35,0,Math.PI*2);ctx.fill();}}
'@)

$lines.Add(@'

// FACE
function drawMoustache(lm){const nose=[lx(lm,2),ly(lm,2)],lip=[lx(lm,13),ly(lm,13)],fw=FW(lm),mW=fw*.38,mH=fw*.12,cx=(nose[0]+lip[0])/2,cy=(nose[1]+lip[1])/2+mH*.2;ctx.fillStyle="#3b1f00";ctx.beginPath();ctx.moveTo(cx,cy);ctx.bezierCurveTo(cx-mW*.1,cy-mH*.8,cx-mW*.5,cy-mH,cx-mW*.6,cy-mH*.3);ctx.bezierCurveTo(cx-mW*.7,cy+mH*.3,cx-mW*.2,cy+mH*.3,cx,cy);ctx.fill();ctx.beginPath();ctx.moveTo(cx,cy);ctx.bezierCurveTo(cx+mW*.1,cy-mH*.8,cx+mW*.5,cy-mH,cx+mW*.6,cy-mH*.3);ctx.bezierCurveTo(cx+mW*.7,cy+mH*.3,cx+mW*.2,cy+mH*.3,cx,cy);ctx.fill();}
function drawBeard(lm){const fw=FW(lm),fh=FH(lm),cx=CX(lm),chin=ly(lm,175),lC=lx(lm,234),rC=lx(lm,454);ctx.fillStyle="#3b1f00";ctx.beginPath();ctx.moveTo(lC+fw*.05,chin-fh*.2);ctx.bezierCurveTo(lC-fw*.05,chin,cx-fw*.1,chin+fh*.35,cx,chin+fh*.4);ctx.bezierCurveTo(cx+fw*.1,chin+fh*.35,rC+fw*.05,chin,rC-fw*.05,chin-fh*.2);ctx.closePath();ctx.fill();}
function drawLips(lm){const lC=lx(lm,61),rC=lx(lm,291),lipY=ly(lm,13),lw=Math.abs(rC-lC);ctx.fillStyle="#cc1144";ctx.beginPath();ctx.moveTo(lC,lipY);ctx.bezierCurveTo(lC+lw*.2,lipY-lw*.1,rC-lw*.2,lipY-lw*.1,rC,lipY);ctx.bezierCurveTo(rC-lw*.2,lipY+lw*.15,lC+lw*.2,lipY+lw*.15,lC,lipY);ctx.closePath();ctx.fill();ctx.fillStyle="rgba(255,200,200,.4)";ctx.beginPath();ctx.ellipse((lC+rC)/2,lipY-lw*.02,lw*.28,lw*.06,0,0,Math.PI*2);ctx.fill();}
function drawBlush(lm){const fw=FW(lm);[[lx(lm,234)+fw*.05,ly(lm,234)],[lx(lm,454)-fw*.05,ly(lm,454)]].forEach(([px,py])=>{const g=ctx.createRadialGradient(px,py,0,px,py,fw*.14);g.addColorStop(0,"rgba(255,100,120,.42)");g.addColorStop(1,"rgba(255,100,120,0)");ctx.beginPath();ctx.ellipse(px,py,fw*.17,fw*.1,0,0,Math.PI*2);ctx.fillStyle=g;ctx.fill();});}
function drawFreckles(lm){const fw=FW(lm),lC=[lx(lm,234),ly(lm,234)],rC=[lx(lm,454),ly(lm,454)];ctx.fillStyle="rgba(139,90,43,.7)";[[lC[0]+fw*.05,lC[1]-fw*.04],[lC[0]+fw*.1,lC[1]],[lC[0]+fw*.07,lC[1]+fw*.04],[lC[0]+fw*.14,lC[1]+fw*.01],[rC[0]-fw*.05,rC[1]-fw*.04],[rC[0]-fw*.1,rC[1]],[rC[0]-fw*.07,rC[1]+fw*.04],[rC[0]-fw*.14,rC[1]+fw*.01]].forEach(([px,py])=>{ctx.beginPath();ctx.arc(px,py,fw*.017,0,Math.PI*2);ctx.fill();});}
function drawFangs(lm){const lC=lx(lm,61),rC=lx(lm,291),lipY=ly(lm,17),lw=Math.abs(rC-lC),fw2=FW(lm)*.055,fh=FW(lm)*.12;ctx.fillStyle="#fff";ctx.strokeStyle="#ccc";ctx.lineWidth=1;[lC+lw*.2,lC+lw*.4].forEach(fx=>{ctx.beginPath();ctx.moveTo(fx-fw2/2,lipY);ctx.lineTo(fx+fw2/2,lipY);ctx.lineTo(fx,lipY+fh);ctx.closePath();ctx.fill();ctx.stroke();});}
function drawEyepatch(lm){const e=eyeInfo(lm),fw=FW(lm),r=e.dist*.56;ctx.fillStyle="#111";ctx.beginPath();ctx.ellipse(e.lEx,e.lEy,r/1.3,r/1.8,0,0,Math.PI*2);ctx.fill();ctx.strokeStyle="#555";ctx.lineWidth=2.5;ctx.stroke();ctx.strokeStyle="#111";ctx.lineWidth=3.5;ctx.beginPath();ctx.moveTo(e.lEx-r/1.3,e.lEy);ctx.lineTo(e.lEx-fw*.38,e.lEy-fw*.05);ctx.stroke();ctx.beginPath();ctx.moveTo(e.lEx+r/1.3,e.lEy);ctx.lineTo(e.lEx+fw*.38,e.lEy-fw*.05);ctx.stroke();}

// EFFECTS
function drawBigHead(){const cx=videoWidth/2,cy=videoHeight/2;ctx.save();ctx.translate(cx,cy);ctx.scale(1.35,1.35);ctx.translate(-cx,-cy);ctx.scale(-1,1);ctx.translate(-videoWidth,0);ctx.drawImage(video,0,0,videoWidth,videoHeight);ctx.restore();}
function drawTears(lm){const fh=FH(lm);[[lx(lm,33),ly(lm,33)],[lx(lm,263),ly(lm,263)]].forEach(([ex,ey])=>{const g=ctx.createLinearGradient(ex,ey,ex,ey+fh*.42);g.addColorStop(0,"rgba(100,180,255,.9)");g.addColorStop(1,"rgba(100,180,255,0)");ctx.fillStyle=g;ctx.beginPath();ctx.moveTo(ex-4,ey+5);ctx.bezierCurveTo(ex-7,ey+fh*.2,ex+7,ey+fh*.28,ex+4,ey+fh*.42);ctx.bezierCurveTo(ex-4,ey+fh*.28,ex-9,ey+fh*.2,ex-4,ey+5);ctx.fill();});}
function drawRainbowAura(lm){const t=frameTime/220,cx=lx(lm,1),cy=ly(lm,1),fw=FW(lm);["#ff0","#f0f","#0ff","#f80","#0f0","#08f"].forEach((c,i)=>{const a=t+i/6*Math.PI*2;ctx.font=(fw*.11)+"px serif";ctx.fillStyle=c;ctx.fillText(["*","o","+","x","@","#"][i],cx+Math.cos(a)*fw*.72,cy+Math.sin(a)*fw*.4);});}
function drawStarAura(lm){const t=frameTime/320,cx=lx(lm,1),cy=ly(lm,1),fw=FW(lm);for(let i=0;i<6;i++){const a=i/6*Math.PI*2+t,r=fw*(.6+Math.sin(t+i)*.07),x=cx+Math.cos(a)*r,y=cy+Math.sin(a)*r*.6;ctx.save();ctx.translate(x,y);ctx.rotate(a+t);ctx.globalAlpha=.5+Math.sin(t*2+i)*.5;ctx.font=(fw*.1)+"px serif";ctx.textAlign="center";ctx.textBaseline="middle";ctx.fillText("*",0,0);ctx.globalAlpha=1;ctx.restore();}}

// FUN
function drawBow(lm){const h=headTop(lm),bw=h.fw*.25,bh=h.fw*.14,bx=h.cx,by=h.topY-h.fw*.05;ctx.fillStyle="#ff69b4";ctx.beginPath();ctx.moveTo(bx,by);ctx.bezierCurveTo(bx-bw,by-bh,bx-bw,by+bh,bx,by);ctx.fill();ctx.beginPath();ctx.moveTo(bx,by);ctx.bezierCurveTo(bx+bw,by-bh,bx+bw,by+bh,bx,by);ctx.fill();ctx.fillStyle="#f06292";ctx.beginPath();ctx.arc(bx,by,h.fw*.04,0,Math.PI*2);ctx.fill();}
function drawMonocle(lm){const e=eyeInfo(lm),r=e.dist*.55;ctx.strokeStyle="#B8860B";ctx.lineWidth=3.5;ctx.beginPath();ctx.arc(e.rEx,e.rEy,r/1.5,0,Math.PI*2);ctx.stroke();ctx.setLineDash([3,4]);ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(e.rEx+r/1.5,e.rEy);ctx.lineTo(e.rEx+r*1.6,e.rEy+r*1.5);ctx.stroke();ctx.setLineDash([]);}

// EXPRESSIONS
let lastMouth=0,lastSmile=0,lastBlink=0;
function handleExpressions(bs,lm){
  const get=n=>{const e=bs.categories?.find(c=>c.categoryName===n);return e?e.score:0;};
  const now=frameTime,mo=get("jawOpen"),sl=get("mouthSmileLeft"),sr=get("mouthSmileRight"),lb=get("eyeBlinkLeft"),rb=get("eyeBlinkRight");
  if(mo>0.55&&now-lastMouth>500){spawn(lx(lm,13),ly(lm,13),["boom","pow","wow","lol"],6);lastMouth=now;}
  if((sl+sr)>0.9&&now-lastSmile>800){spawn(lx(lm,33),ly(lm,33),["<3","*","xo"],4);lastSmile=now;}
  if((lb>0.75||rb>0.75)&&now-lastBlink>700){spawn(lx(lm,33),ly(lm,33),["*","~","!"],4);lastBlink=now;}
}

// SCREENSHOT
function takeScreenshot(){
  const btn=document.getElementById("btn-screenshot");
  if(btn)btn.textContent="Snapping...";
  setTimeout(()=>{
    const tmp=document.createElement("canvas");
    tmp.width=canvas.width;tmp.height=canvas.height+52;
    const tc=tmp.getContext("2d");
    const g=tc.createLinearGradient(0,canvas.height,0,canvas.height+52);
    g.addColorStop(0,"#7c3aed");g.addColorStop(1,"#ff4fa3");
    tc.fillStyle=g;tc.fillRect(0,0,tmp.width,tmp.height);
    tc.drawImage(canvas,0,0);
    const cap=CAPTIONS[Math.floor(Math.random()*CAPTIONS.length)];
    tc.fillStyle="#fff";tc.font="bold 15px Inter,sans-serif";tc.textAlign="center";
    tc.fillText(cap,tmp.width/2,canvas.height+33);
    const a=document.createElement("a");a.href=tmp.toDataURL("image/png");
    a.download="funny-face-"+Date.now()+".png";a.click();
    if(btn)btn.textContent="Snap!";
  },80);
}

// UI
function setupUI(){
  const controls=document.getElementById("filter-controls");
  const cats={};
  FILTER_DEFS.forEach(f=>{if(!cats[f.cat])cats[f.cat]=[];cats[f.cat].push(f);});
  Object.keys(cats).forEach(cat=>{
    const sec=document.createElement("div");sec.className="filter-section";
    const lbl=document.createElement("div");lbl.className="cat-label";lbl.textContent=cat;sec.appendChild(lbl);
    cats[cat].forEach(f=>{
      const btn=document.createElement("button");btn.className="filter-btn";btn.id="btn-"+f.id;btn.textContent=f.label;
      btn.onclick=()=>{filters[f.id]=!filters[f.id];btn.classList.toggle("active",filters[f.id]);};
      sec.appendChild(btn);
    });
    controls.appendChild(sec);
  });
  const acts=document.createElement("div");acts.className="filter-section";
  const al=document.createElement("div");al.className="cat-label";al.textContent="Actions";acts.appendChild(al);
  const clr=document.createElement("button");clr.className="filter-btn danger";clr.textContent="Clear All";
  clr.onclick=()=>{Object.keys(filters).forEach(k=>filters[k]=false);document.querySelectorAll(".filter-btn").forEach(b=>b.classList.remove("active"));};
  acts.appendChild(clr);
  const snap=document.createElement("button");snap.className="filter-btn capture";snap.id="btn-screenshot";snap.textContent="Snap!";
  snap.onclick=takeScreenshot;acts.appendChild(snap);
  controls.appendChild(acts);
}

function main(){setupUI();initCamera();initFaceModel();}
main();
'@)

$content = $lines -join "`n"
[System.IO.File]::WriteAllText("c:\Users\Waseem\Downloads\munataha\script.js", $content, $utf8NoBom)
Write-Host "Done: $($content.Length) chars, $($content.Split("`n").Count) lines"
