using System.IO;
using System.Text.Json;
namespace KarimEldamatyWindows;
public static class NotionHTMLExport
{
    public static void ExportNotionHtml(Board board,string path,byte[] png) => File.WriteAllText(path,Html(board,png));
    public static string Html(Board board,byte[] png)
    {
        BoardCodec.Validate(board);
        if(png.Length is 0 or > 50000000)throw new InvalidDataException("The drawing image could not be prepared for the HTML copy.");
        var payload=new{id=board.Id.ToString().ToUpperInvariant(),title=board.Title,width=board.Width,height=board.Height,pointsPerMM=board.PointsPerMM,scaleDenominator=board.ScaleDenominator,nativeURL=CraftExchange.NativeLink(board),image="data:image/png;base64,"+Convert.ToBase64String(png)};
        return Template.Replace("__BOARD_PAYLOAD__",JsonSerializer.Serialize(payload));
    }
    private const string Template="""
<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'">
<title>SketchGlide Windows 11 · 0.2 Test</title>
<style>
:root{color-scheme:light;--bg:#edf4f5;--glass:#ffffffd9;--ink:#17282f;--border:#b7cbd0;--muted:#566e77}*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:13px -apple-system,BlinkMacSystemFont,sans-serif}body.dark{color-scheme:dark;--bg:#16232b;--glass:#24373fdd;--ink:#e2f3f5;--border:#49616a;--muted:#b5cbd1}
header{display:flex;align-items:center;gap:10px;padding:14px 18px;background:var(--glass);border-bottom:1px solid var(--border);position:sticky;top:0;z-index:2;backdrop-filter:blur(16px)}
.title{flex:1;min-width:120px}strong{display:block;font-size:16px}.muted{font-size:11px;color:var(--muted)}
button,select,input{font:inherit;border:1px solid var(--border);border-radius:8px;background:var(--glass);color:var(--ink);padding:7px 9px}button{cursor:pointer}button.active{background:#0b7770;color:white}button:disabled{opacity:.4;cursor:default}
nav{display:flex;gap:7px;align-items:center;flex-wrap:wrap;padding:10px 18px}input[type=color]{width:36px;height:33px;padding:3px}input[type=range]{max-width:110px}#surface{overflow:auto;height:65vh;min-height:320px;margin:0 16px;border-radius:14px;border:1px solid var(--border);background:#bccbd0}
canvas{display:block;touch-action:none;max-width:none}footer{display:flex;gap:14px;flex-wrap:wrap;padding:12px 18px;color:var(--muted);font-size:11px}a{color:inherit}#notice{flex:1}
@media(max-width:600px){header{padding:10px}nav{padding:8px;gap:5px}#surface{margin:0 8px}strong{font-size:14px}}
</style><header><div class="title"><strong>SketchGlide <span class="muted">Windows 11 · 0.2 Test</span></strong><span id="name" class="muted"></span></div><button id="theme" aria-label="Toggle light or dark appearance">Light / Dark</button></header>
<nav><button id="pen" class="active">Pen</button><button id="erase">Erase new ink</button><select id="brush" aria-label="Brush"><option value="fineliner">Fineliner</option><option value="pressure">Pressure pen</option><option value="marker">Highlighter</option></select><input id="color" type="color" value="#182b34" aria-label="Ink colour"><input id="width" type="range" min="1" max="30" value="4" aria-label="Pen width"><button id="undo">Undo</button><button id="redo">Redo</button><button id="png">Download PNG</button><button id="save">Save new ink</button><label>Load ink <input id="load" type="file" accept=".json,application/json" style="max-width:180px"></label></nav>
<div id="surface"><canvas id="board" aria-label="Interactive drawing copy"></canvas></div><footer><span id="notice">Ready</span><a id="native">Open native board on Windows</a><span>Web copy: existing artwork is a background image. New ink is editable. Cloud sync is not enabled.</span></footer>
<script>
'use strict';
const source = __BOARD_PAYLOAD__;
const $=id=>document.getElementById(id), canvas=$('board'), context=canvas.getContext('2d');
const ratio=Math.min(1,1800/Math.max(source.width,source.height)), w=Math.max(1,Math.round(source.width*ratio)), h=Math.max(1,Math.round(source.height*ratio));
const dpr=Math.min(2,window.devicePixelRatio||1);canvas.width=Math.round(w*dpr);canvas.height=Math.round(h*dpr);canvas.style.width=w+'px';canvas.style.height=h+'px';context.scale(dpr,dpr);
$('name').textContent=source.title+' · offline web drawing copy';$('native').href=source.nativeURL;
const image=new Image();let ready=false,strokes=[],history=[],redo=[],active=null,activePointer=null,tool='pen',dirty=false,scheduled=false;
const storageKey='karimboard.web.'+source.id;let localSave=true;
function say(text){$('notice').textContent=text}
function validStroke(s){return s&&/^#[a-f0-9]{6}$/i.test(s.color)&&Number.isFinite(s.width)&&s.width>=1&&s.width<=30&&['fineliner','pressure','marker'].includes(s.brush)&&Array.isArray(s.points)&&s.points.length>0&&s.points.length<=100000&&s.points.every(p=>Array.isArray(p)&&p.length===3&&p.every(Number.isFinite)&&Math.abs(p[0])<=1000000&&Math.abs(p[1])<=1000000&&p[2]>=0&&p[2]<=1)}
function widthAt(s,p){return s.width*(s.brush==='pressure'?.2+.8*p[2]:1)}
function stroke(s){context.strokeStyle=s.color;context.fillStyle=s.color;context.globalAlpha=s.brush==='marker'?.3:1;context.lineCap='round';context.lineJoin='round';
  if(s.points.length===1){const p=s.points[0];context.beginPath();context.arc(p[0]*ratio,p[1]*ratio,widthAt(s,p)*ratio/2,0,Math.PI*2);context.fill()}
  for(let i=1;i<s.points.length;i++){const a=s.points[i-1],b=s.points[i];context.lineWidth=Math.max(.3,(widthAt(s,a)+widthAt(s,b))*ratio/2);context.beginPath();context.moveTo(a[0]*ratio,a[1]*ratio);context.lineTo(b[0]*ratio,b[1]*ratio);context.stroke()}context.globalAlpha=1}
function render(){scheduled=false;if(!ready)return;context.clearRect(0,0,w,h);context.drawImage(image,0,0,w,h);strokes.forEach(stroke);if(active)stroke(active);$('undo').disabled=!history.length;$('redo').disabled=!redo.length}
function requestRender(){$('undo').disabled=!history.length;$('redo').disabled=!redo.length;if(!scheduled){scheduled=true;requestAnimationFrame(render)}}
function persist(){if(!localSave)return;try{localStorage.setItem(storageKey,JSON.stringify(strokes));say('New ink saved in this browser. Download a copy before leaving an embedded page.')}catch(e){localSave=false;say('Autosave unavailable here. Use Save new ink before leaving.')}}
try{const saved=JSON.parse(localStorage.getItem(storageKey)||'[]');if(Array.isArray(saved)&&saved.length<=2000&&saved.every(validStroke))strokes=saved}catch(e){localSave=false}
image.onload=()=>{ready=true;render();say(localSave?'Draw here. Download new ink to keep a portable copy.':'Autosave unavailable in this embed. Use Save new ink.')};image.src=source.image;
function point(e){const r=canvas.getBoundingClientRect();return[(e.clientX-r.left)/ratio,(e.clientY-r.top)/ratio,e.pointerType==='pen'?Math.max(0,Math.min(1,e.pressure)):0.5]}
function distance(p,a,b){const dx=b[0]-a[0],dy=b[1]-a[1],len=dx*dx+dy*dy,t=len?Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/len)):0;return Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)}
function eraseAt(p){let best=-1,dist=16/ratio;for(let i=strokes.length-1;i>=0;i--){if(strokes[i].points.some((q,n)=>distance(p,strokes[i].points[Math.max(0,n-1)],q)<dist+strokes[i].width/2)){best=i;break}}if(best>=0){if(!dirty)history.push(structuredClone(strokes));strokes.splice(best,1);redo=[];dirty=true;requestRender()}}
canvas.addEventListener('pointerdown',e=>{if(!ready||e.button!==0||activePointer!==null)return;activePointer=e.pointerId;canvas.setPointerCapture(e.pointerId);dirty=false;if(tool==='erase'){eraseAt(point(e));return}active={color:$('color').value,width:Number($('width').value),brush:$('brush').value,points:[point(e)]};requestRender();e.preventDefault()});
canvas.addEventListener('pointermove',e=>{if(!canvas.hasPointerCapture(e.pointerId))return;if(tool==='erase'){eraseAt(point(e));return}if(!active)return;const batch=e.getCoalescedEvents?e.getCoalescedEvents():[];const events=batch.length?batch:[e];for(const sample of events){const p=point(sample),last=active.points[active.points.length-1];if(Math.hypot(p[0]-last[0],p[1]-last[1])*ratio>=.2){if(active.points.length<100000)active.points.push(p)}}requestRender()});
function finish(e){if(e.pointerId!==activePointer)return;if(active){const p=point(e),last=active.points[active.points.length-1];if(Number.isFinite(p[0])&&Math.hypot(p[0]-last[0],p[1]-last[1])*ratio>.2)active.points.push([p[0],p[1],last[2]]);history.push(structuredClone(strokes));strokes.push(active);active=null;redo=[];dirty=true}if(canvas.hasPointerCapture(e.pointerId))canvas.releasePointerCapture(e.pointerId);activePointer=null;if(dirty)persist();requestRender()}
canvas.addEventListener('pointerup',finish);canvas.addEventListener('pointercancel',e=>{if(e.pointerId!==activePointer)return;active=null;if(tool==='erase'&&dirty&&history.length){strokes=history.pop();persist()}if(canvas.hasPointerCapture(e.pointerId))canvas.releasePointerCapture(e.pointerId);activePointer=null;dirty=false;requestRender()});
function setTool(t){if(activePointer!==null&&canvas.hasPointerCapture(activePointer))canvas.releasePointerCapture(activePointer);activePointer=null;if(active){history.push(structuredClone(strokes));strokes.push(active);active=null;redo=[];persist()}tool=t;$('pen').classList.toggle('active',t==='pen');$('erase').classList.toggle('active',t==='erase');requestRender()}
$('pen').onclick=()=>setTool('pen');$('erase').onclick=()=>setTool('erase');$('theme').onclick=()=>document.body.classList.toggle('dark');
$('undo').onclick=()=>{if(history.length){redo.push(structuredClone(strokes));strokes=history.pop();persist();requestRender()}};$('redo').onclick=()=>{if(redo.length){history.push(structuredClone(strokes));strokes=redo.pop();persist();requestRender()}};
function download(data,name,type){const blob=new Blob([data],{type}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000)}
$('save').onclick=()=>download(JSON.stringify({format:'karimboard-web-ink',version:1,boardID:source.id,width:source.width,height:source.height,strokes},null,2),'Karim-Eldamaty-new-ink.json','application/json');
$('png').onclick=()=>{if(active){say('Finish the current stroke first.');return}render();canvas.toBlob(blob=>{if(blob)download(blob,'Karim-Eldamaty-board.png','image/png')})};
$('load').onchange=async e=>{try{const file=e.target.files[0];if(!file)return;if(file.size>10000000)throw Error('File is too large');const data=JSON.parse(await file.text());if(data.format!=='karimboard-web-ink'||data.version!==1||data.boardID!==source.id||!Array.isArray(data.strokes)||data.strokes.length>2000||!data.strokes.every(validStroke))throw Error('Choose a matching saved web ink file');history.push(structuredClone(strokes));strokes=data.strokes;redo=[];active=null;persist();requestRender()}catch(e){say(e.message)}finally{e.target.value=''}};
window.KarimBoardTest={getState:()=>({ready,count:strokes.length,localSave,width:w,height:h}),distance,importInk:s=>{if(!Array.isArray(s)||!s.every(validStroke))throw Error('Invalid ink');history.push(structuredClone(strokes));strokes=s;redo=[];requestRender()}};
</script></html>
""";
}
