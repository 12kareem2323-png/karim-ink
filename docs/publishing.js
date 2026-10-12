"use strict";
(() => {
  const inputs=[...document.querySelectorAll('[data-publish-step]')];
  if(!inputs.length)return;
  const key='sketchglide-publishing-checklist-v1';
  let saved={};
  try { const value=JSON.parse(localStorage.getItem(key)||'{}'); if(value&&typeof value==='object'&&!Array.isArray(value))saved=value; } catch (_) {}
  for(const input of inputs)input.checked=saved[input.dataset.publishStep]===true;
  function update(persist=true) {
    const checked=inputs.filter(input=>input.checked).length;
    document.querySelector('[data-checklist-progress]').textContent=`${checked} of ${inputs.length} steps marked complete on this browser. These marks do not confirm Store approval.`;
    if(persist)try{localStorage.setItem(key,JSON.stringify(Object.fromEntries(inputs.map(input=>[input.dataset.publishStep,input.checked]))));}catch(_){}
  }
  inputs.forEach(input=>input.addEventListener('change',()=>update()));
  document.querySelector('[data-reset-checklist]').addEventListener('click',()=>{inputs.forEach(input=>input.checked=false);update();});
  document.querySelector('[data-save-checklist]').addEventListener('click',()=>{
    const lines=['SketchGlide publishing checklist — Karim Eldamaty','',...inputs.map(input=>`${input.checked?'[x]':'[ ]'} ${input.closest('label').innerText.trim()}`),'','Marks are your own preparation notes, not confirmation of submission or approval.','Microsoft: https://storedeveloper.microsoft.com/','Apple: https://developer.apple.com/programs/enroll/'];
    const url=URL.createObjectURL(new Blob([lines.join('\n')],{type:'text/plain;charset=utf-8'}));
    const link=document.createElement('a');link.href=url;link.download='SketchGlide-publishing-checklist.txt';document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
  });
  update(false);
})();
