import test from 'node:test';
import assert from 'node:assert/strict';
import {getDistanceUnit,setDistanceUnit,formatDistance,formatGuiDistanceText,
 distanceInputValue,distanceInputFeet,applyDistanceUnits} from '../distance_units.js';
import {senseLightRows,senseRange} from '../sense_rules.js';
import {JSDOM} from 'jsdom';

test('display convention is 5 ft = 1.5 m; stored feet are reversible',()=>{
 try{
  assert.equal(getDistanceUnit(),'feet');
  assert.equal(formatDistance(30),'30 ft');
  setDistanceUnit('meters');
  assert.equal(formatDistance(5),'1,5 m');
  assert.equal(formatDistance(30),'9 m');
  assert.equal(formatDistance(25),'7,5 m');
  assert.equal(distanceInputValue(30),9);
  assert.equal(distanceInputFeet(9),30);
  assert.equal(senseRange(60),'18 m');
  assert.equal(senseLightRows({darkvision:60})[1].dark,'18 m · luce fioca');
 }finally{setDistanceUnit('feet');}
});
test('normal sight uses DMG outdoor reference and does not pretend to see through darkness',()=>{
 try{
  setDistanceUnit('feet');
  assert.match(senseLightRows()[0].bright,/10\.560 ft/);
  assert.doesNotMatch(senseLightRows()[0].bright,/Linea di vista/);
  setDistanceUnit('meters');
  assert.match(senseLightRows()[0].bright,/3168 m/);
  assert.equal(senseLightRows()[0].dark,'Nessuna');
 }finally{setDistanceUnit('feet');}
});
test('GUI display converts single, paired, and rectangular distances',()=>{
 try{
  setDistanceUnit('meters');
  assert.equal(formatGuiDistanceText('Portata 30 ft, gittata 30/120 ft'),'Portata 9 m, gittata 9 m / 36 m');
  assert.equal(formatGuiDistanceText('Linea 30 × 5 ft'),'Linea 9 m × 1,5 m');
  setDistanceUnit('feet');
  assert.equal(formatGuiDistanceText('30 ft'),'30 ft');
 }finally{setDistanceUnit('feet');}
});

test('the GUI converts numeric labels but not trait descriptions or input values',()=>{
 const dom=new JSDOM('<main><span title="30 ft">Portata 30 ft</span><p class="trait-description">The spell reaches 30 ft.</p><label>Gittata <input value="30"></label></main>');
 const main=dom.window.document.querySelector('main');
 try{
  setDistanceUnit('meters');
  applyDistanceUnits(main);
  assert.match(main.querySelector('span').textContent,/9 m/);
  assert.match(main.querySelector('span').title,/9 m/);
  assert.equal(main.querySelector('.trait-description').textContent,'The spell reaches 30 ft.');
  assert.equal(main.querySelector('input').value,'30');
 }finally{setDistanceUnit('feet');dom.window.close();}
});
