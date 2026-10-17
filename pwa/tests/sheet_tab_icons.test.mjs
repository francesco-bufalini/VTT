import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

const source=relative=>new URL(relative,import.meta.url);
const read=relative=>readFileSync(source(relative),'utf8');

test('eight generated character tab icons are real transparent PNG frames',()=>{
 const png=readFileSync(source('../icons/character_tabs.png'));
 assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
 assert.equal(png.readUInt32BE(16),256);
 assert.equal(png.readUInt32BE(20),32);
 assert.equal(png.readUInt8(25),3,'Indexed PNG keeps transparency and bundle size modest');
 const css=read('../mobile_metal_theme.css');
 assert.match(css,/\/icons\/character_tabs\.png/);
 assert.match(css,/background-size:800% 100%/);
 for(const sheet of ['info','stats','actions','magic','inventory','traits','conditions','origins']){
   assert(css.includes('[data-sheet="'+sheet+'"]'),'Drawer icon for '+sheet);
   assert(css.includes('[data-sheet-icon="'+sheet+'"]'),'Section title icon for '+sheet);
 }
 const ui=read('../ui.js');
 assert(ui.includes('data-sheet-icon'),'The active mobile sheet heading must select artwork');
 const sw=read('../sw.js');
 assert(sw.includes('"/icons/character_tabs.png"'),'The artwork must be cached offline');
});

test('Godot uses the same generated artwork in desktop and touch navigation',()=>{
 // The browser-only CI job uses sparse checkout and intentionally omits vtt/.
 const stylePath=source('../../vtt/creature_sheet_style.gd');
 const areaPath=source('../../vtt/creature_area.gd');
 if(!existsSync(stylePath)||!existsSync(areaPath))return;
 const style=read('../../vtt/creature_sheet_style.gd');
 const area=read('../../vtt/creature_area.gd');
 assert(style.includes('res://pwa/icons/character_tabs.png'));
 assert(style.includes('index * 32, 0, 32, 32'));
 assert(area.includes('.character_tab_icon(title)'),'Desktop TabContainer applies the sprite');
 assert(area.includes('button.icon = _tabs.get_tab_icon(index)'),'Android drawer applies the sprite');
 assert(area.includes('_touch_section.add_icon_item('),'Android section selector applies the sprite');
 const hostPath=source('../../network/pwa_host.gd');
 if(existsSync(hostPath))assert(read('../../network/pwa_host.gd').includes('"/icons/character_tabs.png"'));
});
