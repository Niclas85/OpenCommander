'use strict';
(() => {
 const cases=JSON.parse(document.getElementById('planData').textContent);
 const ids=new Set(cases.map(c=>c.id));
 const statuses=['Nicht ausgeführt','Bestanden','Fehlgeschlagen','Blockiert','Nicht anwendbar'];
 const key='opencommander-testplan-0.3.19-v1';
 const fields=['runName','tester','date','build','environment'];
 const $=id=>document.getElementById(id);
 const cards=[...document.querySelectorAll('.case')];
 let state={schema:1,version:'0.3.19',meta:{date:new Date().toLocaleDateString('sv-SE'),build:'0.3.19 / 84a3365'},results:{}};
 const blank=()=>({status:'Nicht ausgeführt',variant:'',actual:'',evidence:''});
 let storageOK=true;
 function validate(raw){
  if(!raw||raw.schema!==1||raw.version!=='0.3.19'||!raw.meta||typeof raw.meta!=='object'||!raw.results||typeof raw.results!=='object') throw Error('Keine passende Testplan-Sicherung für 0.3.19.');
  const clean={schema:1,version:'0.3.19',meta:{},results:{}};
  for(const f of fields) clean.meta[f]=String(raw.meta[f]||'').slice(0,30000);
  for(const [id,r] of Object.entries(raw.results)){
   if(!ids.has(id)||!r||!statuses.includes(r.status)) throw Error('Unbekannte Fall-ID oder ungültiger Status.');
   clean.results[id]={status:r.status};for(const f of ['variant','actual','evidence']) clean.results[id][f]=String(r[f]||'').slice(0,30000);
  }return clean;
 }
 try{const previous=localStorage.getItem(key);if(previous) state=validate(JSON.parse(previous));if(localStorage.getItem(key+'-theme')==='dark') document.documentElement.dataset.theme='dark';}catch(e){storageOK=false;$('saveStatus').textContent='Lokale Speicherung nicht verfügbar oder Sicherung ungültig. Bitte JSON exportieren. '+e.message;}
 function save(){try{localStorage.setItem(key,JSON.stringify(state));storageOK=true;$('saveStatus').textContent='Lokal gespeichert · '+new Date().toLocaleTimeString('de-CH')+' · Für dauerhafte Sicherung JSON exportieren.';}catch(e){storageOK=false;$('saveStatus').textContent='Nicht dauerhaft gespeichert. Bitte jetzt als JSON exportieren.';}}
 function refresh(){
  const count=Object.fromEntries(statuses.map(s=>[s,0]));
  for(const card of cards){const r=state.results[card.id]||blank();count[r.status]++;const badge=card.querySelector('.badge');badge.textContent=r.status;badge.dataset.status=r.status;}
  const done=cases.length-count['Nicht ausgeführt'];
  $('progress').textContent=`${done} / ${cases.length} bewertet · ${count.Bestanden} bestanden · ${count.Fehlgeschlagen} fehlgeschlagen · ${count.Blockiert} blockiert · ${count['Nicht anwendbar']} nicht anwendbar`;
  $('progressBar').style.width=(count.Bestanden/cases.length*100)+'%';filter();
 }
 function render(){for(const f of fields) $(f).value=state.meta[f]||'';for(const card of cards){const r=state.results[card.id]||blank();for(const field of card.querySelectorAll('[data-field]'))field.value=r[field.dataset.field]||'';}refresh();}
 function filter(){const q=$('search').value.toLocaleLowerCase('de');let shown=0;for(const card of cards){const c=cases.find(c=>c.id===card.id);const text=[c.id,c.title,c.group,c.expected,...c.steps].join(' ').toLocaleLowerCase('de');const r=state.results[c.id]||blank();card.hidden=!!((q&&!text.includes(q))||($('group').value&&card.dataset.group!==$('group').value)||($('priority').value&&c.priority!==$('priority').value)||($('status').value&&r.status!==$('status').value));if(!card.hidden)shown++;}for(const suite of document.querySelectorAll('.suite'))suite.hidden=![...suite.querySelectorAll('.case')].some(c=>!c.hidden);$('visible').textContent=`${shown} von ${cases.length} Fällen angezeigt`;}
 for(const f of fields)$(f).addEventListener('input',()=>{state.meta[f]=$(f).value;save();});
 for(const card of cards)for(const field of card.querySelectorAll('[data-field]'))field.addEventListener('input',()=>{state.results[card.id]={...(state.results[card.id]||blank()),[field.dataset.field]:field.value};save();refresh();});
 for(const id of ['search','group','priority','status'])$(id).addEventListener('input',filter);
 $('clearFilters').onclick=()=>{for(const id of ['search','group','priority','status'])$(id).value='';filter();};
 for(const link of document.querySelectorAll('aside a'))link.addEventListener('click',()=>{for(const id of ['search','group','priority','status'])$(id).value='';filter();});
 $('expand').onclick=()=>cards.filter(c=>!c.hidden).forEach(c=>c.open=true);
 $('collapse').onclick=()=>cards.forEach(c=>c.open=false);
 $('theme').onclick=()=>{const theme=document.documentElement.dataset.theme==='dark'?'light':'dark';document.documentElement.dataset.theme=theme;try{localStorage.setItem(key+'-theme',theme);}catch(e){}};
 function ask(message){$('confirmMessage').textContent=message;const dialog=$('confirmDialog');return new Promise(resolve=>{const done=value=>{dialog.close();resolve(value);};$('confirmYes').onclick=()=>done(true);$('confirmNo').onclick=()=>done(false);dialog.oncancel=event=>{event.preventDefault();done(false);};dialog.showModal();$('confirmNo').focus();});}
 function download(text,type,extension){const blob=new Blob([text],{type});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='OpenCommander-Testlauf-'+(state.meta.runName||state.meta.date||'unbenannt').replace(/[^\p{L}\p{N}._-]+/gu,'-').slice(0,80)+'.'+extension;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
 $('exportJson').onclick=()=>download(JSON.stringify({...state,exportedAt:new Date().toISOString()},null,2),'application/json','json');
 // Prefix spreadsheet formula starters in user-entered CSV text to keep exports inert.
 const cell=v=>{let s=String(v??'');if(/^[\s]*[=+@-]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';};
 $('exportCsv').onclick=()=>{const rows=[['ID','Bereich','Priorität','Titel','Voraussetzungen','Schritte','Erwartet','Status','Variante','Ist-Ergebnis','Nachweis / Ticket','Lauf','Tester','Datum','Build','Umgebung']];for(const c of cases){const r=state.results[c.id]||blank();rows.push([c.id,c.group,c.priority,c.title,c.prerequisites,c.steps.join(' → '),c.expected,r.status,r.variant,r.actual,r.evidence,state.meta.runName,state.meta.tester,state.meta.date,state.meta.build,state.meta.environment]);}download('\ufeff'+rows.map(r=>r.map(cell).join(';')).join('\r\n'),'text/csv;charset=utf-8','csv');};
 $('importButton').onclick=()=>$('importJson').click();
 $('importJson').onchange=async event=>{const file=event.target.files[0];if(!file)return;try{if(file.size>5*1024*1024)throw Error('Sicherung größer als 5 MiB.');const next=validate(JSON.parse(await file.text()));if(!await ask('Aktuellen Lauf durch diese Sicherung ersetzen? Vorher bei Bedarf exportieren.'))return;state=next;save();render();}catch(e){$('saveStatus').textContent='Import nicht möglich: '+e.message;}finally{event.target.value='';}};
 $('newRun').onclick=async()=>{if(!await ask('Neuen leeren Lauf beginnen? Aktuelle Ergebnisse vorher als JSON/CSV exportieren.'))return;state={schema:1,version:'0.3.19',meta:{date:new Date().toLocaleDateString('sv-SE'),build:'0.3.19 / 84a3365'},results:{}};save();render();};
 let printOpen=[];
 function preparePrint(){printOpen=cards.map(c=>c.open);for(const card of cards){card.open=true;let p=card.querySelector('.print-result');if(!p){p=document.createElement('p');p.className='print-result';card.querySelector('.case-body').append(p);}const r=state.results[card.id]||blank();p.textContent=`Status: ${r.status}\nVariante: ${r.variant||'—'}\nIst-Ergebnis: ${r.actual||'—'}\nNachweis: ${r.evidence||'—'}`;}const env=$('environment');let p=env.parentElement.querySelector('.print-result');if(!p){p=document.createElement('p');p.className='print-result';env.parentElement.append(p);}p.textContent=env.value||'—';}
 window.addEventListener('beforeprint',preparePrint);window.addEventListener('afterprint',()=>cards.forEach((c,i)=>c.open=printOpen[i]||false));$('print').onclick=()=>window.print();
 render();
})();
