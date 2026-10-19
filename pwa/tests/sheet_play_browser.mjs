import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';
const f=await browserFixture({live:true});const {page,context,origin,errors,missing,writes,sheet,popup,dismiss,shot}=f;
const record=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;});
try{
 await seedPlayCreature(page,origin);
 // The same optional maneuver used by Poteri must now appear only in battle resources.
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const row=(await listCreatures())[0],creature=row.creature;
  await saveCreature({...creature,
   resource_trackers:[...(creature.resource_trackers||[]),
     {id:'superiority',name:'Superiority Die',max:4,recharge:'short_rest'}],
   optional_features_catalog:[...(creature.optional_features_catalog||[]),
     {name:"Commander's Strike",source:'PHB',origin_name:'Manovra'}],
   action_grants:[...(creature.action_grants||[]),
     {id:'arcane_pulse',name:'Impulso arcano',action_type:'bonus',origin_id:'feature:class|phb|wizard|arcane_pulse',
      tracker_id:'focus',tracker_cost:2,description:'Attiva un impulso magico.'},
     {id:'free_pulse',name:'Impulso gratuito',action_type:'free',origin_id:'feature:class|phb|wizard|free_pulse',
      tracker_cost:0,description:'Attiva un impulso gratuito.'}],
   origin_spell_grants:[...(creature.origin_spell_grants||[]),
     {id:'arcane_light',spell_id:'spell:light|phb',tracker_id:'focus',
      payment_mode:'tracker',tracker_cost:1,origin_id:'feature:class|phb|wizard|arcane_light',
      origin_name:'Mago'}]},
   'default',row.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await page.locator('#sheet-play-view').waitFor();
 for(const viewport of [{width:320,height:740},{width:360,height:800},{width:390,height:844},{width:430,height:932},{width:844,height:390}]){
  await page.setViewportSize(viewport);
  for(const key of ['info','battle','magic','inventory','conditions','origins']){
   await sheet(key);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),key+' overflow at '+viewport.width);
   const inlineEditors=page.locator('#sheet-play-view input:not([type=search]):visible,#sheet-play-view select:visible,#sheet-play-view textarea:visible');
   assert.equal(await inlineEditors.count(),key==='inventory'?5:0,
     'Only the five coin amounts are editable inline: '+key);
   if(key==='inventory')assert.equal(await page.locator('#sheet-play-view .inventory-play-coins input[data-coin-code]').count(),5,
     'Visible direct inventory editors must be the five currency inputs');
   if(viewport.width===390)await shot(key);
  }
 }
 await page.setViewportSize({width:390,height:844});
 await sheet('info');await popup('identity');await page.locator('#sheet-context-dialog [data-field="name"]').fill('Lyria, guardiana della Luna');
 await page.keyboard.press('Escape');await page.locator('#sheet-context-dialog').waitFor({state:'detached'});
 assert.equal((await record()).name,'Lyria, guardiana della Luna');assert.match(await page.locator('.play-identity h2').textContent(),/guardiana/);
 await sheet('battle');
 const weaponPanel=page.locator('#sheet-play-view [data-battle-action="attacks"]');
 const movementPanel=page.locator('#sheet-play-view [data-battle-action="movement"]');
 assert.equal(await weaponPanel.count(),1);assert.equal(await weaponPanel.getAttribute('open'),'');
 assert.match(await weaponPanel.locator('summary.play-battle-summary').textContent(),/Attacchi fisici/);
 const otherPanel=page.locator('#sheet-play-view [data-battle-action="others"]');

 assert.equal(await otherPanel.count(),1);
 assert.equal(await page.locator('#sheet-play-view [data-battle-action="abilities"]').count(),0,'Abilities belong beneath resources');
 assert.match(await otherPanel.locator('summary.play-battle-summary').textContent(),/Altre azioni/);
 await otherPanel.locator('summary.play-battle-summary').click();
 const searchAction=otherPanel.locator('[data-attack-id="search"]');
 assert.equal(await searchAction.locator('[data-target="skill:perception"]').count(),1);
 assert.equal(await searchAction.locator('[data-target="skill:investigation"]').count(),1);
 assert.equal(await searchAction.locator('.play-battle-effect').count(),0);
 const alternativeRolls=await searchAction.locator('.play-battle-attack-roll').evaluateAll(nodes=>
   nodes.map(node=>{const {x,y,right}=node.getBoundingClientRect();return {x,y,right}}));
 assert.equal(alternativeRolls.length,2);
 assert(alternativeRolls[1].y>alternativeRolls[0].y+10,'Alternative dice buttons must stack');
 await otherPanel.locator('summary.play-battle-summary').click();
 const spellPanel=page.locator('#sheet-play-view [data-battle-action="spells"]');
 assert.equal(await spellPanel.count(),1);
 assert.equal(await weaponPanel.locator('.play-chevron').count(),0,'No disclosure arrow in attack header');
 assert.equal(await spellPanel.locator('.play-chevron').count(),0,'No disclosure arrow in spell header');
 assert.equal(await page.locator('.play-battle-heading-tools [data-sheet-context="equipment"]').count(),1);
 assert.equal(await page.locator('.play-battle-heading-tools [data-act="action-open-spells"]').count(),1);
 await spellPanel.locator('summary.play-battle-summary').click();
 assert.equal(await spellPanel.getAttribute('open'),'');
 const combatSpells=spellPanel.locator('.play-battle-spell-entry');
 assert(await combatSpells.count()>=2,'Prepared slot spells and grants appear in the unified spell list');
 assert(await spellPanel.locator('[data-action-timing="action"] .play-battle-spell-entry[data-spell-id="spell:light|phb"]').count()>=1);
 assert.equal(await spellPanel.locator('[data-action-timing="reaction"] .play-battle-spell-entry[data-spell-id="spell:shield|phb"]').count(),1);
 assert.equal(await spellPanel.locator('.action-economy-preview').count(),0,'Spell descriptions remain hidden until opened');
 const lightEntry=spellPanel.locator('[data-spell-id="spell:light|phb"]').first();
 assert.match(await lightEntry.textContent(),/Trucchetto/);
 await lightEntry.locator('[data-act="action-cast-spell"]').click();
 assert.match(await page.locator('#action-cast-dialog').textContent(),/Light/);
 assert(await page.locator('#action-cast-dialog .magic-spell-facts').count(),
   'The same detailed Magia spell dialog opens from the action row');
 await page.locator('#action-cast-dialog [data-act="action-cast-cancel"]').click();
 await spellPanel.locator('summary.play-battle-summary').click();

 const mainAttack=weaponPanel.locator('[data-attack-id="item:local_sword"]');
 assert.equal(await mainAttack.count(),1);
 const mainTiming=weaponPanel.locator('[data-action-timing="action"]');
 assert.equal(await mainTiming.locator('summary.play-battle-action-heading').count(),1);
 assert.equal(await mainTiming.getAttribute('open'),'');
 await mainTiming.locator('summary.play-battle-action-heading').click();
 assert.equal(await mainTiming.getAttribute('open'),null,'Tapping the timing label collapses its actions');
 await mainTiming.locator('summary.play-battle-action-heading').click();
 assert.equal(await mainTiming.getAttribute('open'),'','Tapping again expands without any extra icon');
 const opportunity=weaponPanel.locator('[data-attack-id="opportunity"]');
 assert.match(await opportunity.locator('.play-battle-attack-copy strong').textContent(),/Attacco di opportunità/);
 assert.equal(await opportunity.locator('[data-act="battle-damage-roll"]').count(),1);
 assert.equal(await mainAttack.locator('details').getAttribute('open'),null);
 assert.match(await mainAttack.locator('.play-battle-roll-formula').textContent(),/1d20 \+ [0-9]+ · Mischia/);
 assert.equal(await weaponPanel.locator('[data-attack-id="item:local_sword"]').count(),1);
 assert.equal(await weaponPanel.locator('.play-battle-attack-copy strong').filter({hasText:/^Attaccare$/}).count(),0);
 await mainAttack.locator('summary').click();
 assert.equal(await mainAttack.locator('details').getAttribute('open'),'');
 assert.match(await mainAttack.locator('.play-battle-attack-expanded').textContent(),/The most common action/);
 await mainAttack.locator('summary').click();
 assert.equal(await mainAttack.locator('.play-battle-attack-chevron').count(),0);
 assert.equal(await mainAttack.locator('.play-battle-effect').count(),1);
 const damageButton=mainAttack.locator('[data-act="battle-damage-roll"]');
 assert.equal(await damageButton.count(),1);
 await damageButton.click();
 assert.match(await page.locator('#battle-damage-dialog').textContent(),/Lama lunare/);
 await page.locator('#battle-damage-dialog [data-act="battle-damage-confirm"]').click();
 assert.match(await page.locator('#battle-damage-dialog [data-damage-result]').textContent(),/Formula/);
 await page.locator('#battle-damage-dialog [data-act="battle-damage-close"]').click();
 await mainAttack.locator('[data-target="attack_hit:item:local_sword"]').click();
 assert.equal(await mainAttack.locator('details').getAttribute('open'),null,'Dice trigger must not expand description');
 assert.match(await page.locator('#sheet-roll-dialog [data-roll-formula]').textContent(),/1d20/);
 await page.locator('#sheet-roll-dialog [data-act="close-sheet-roll"]').click();
 assert.equal(await movementPanel.getAttribute('open'),null);
 await movementPanel.locator('summary.play-battle-summary').click();
 const escapeAction=movementPanel.locator('[data-attack-id="escape_grapple"]');
 assert.equal(await escapeAction.locator('[data-target="skill:athletics"]').count(),1);
 assert.equal(await escapeAction.locator('[data-target="skill:acrobatics"]').count(),1);
 const escapeRolls=await escapeAction.locator('.play-battle-attack-roll').evaluateAll(nodes=>
   nodes.map(node=>{const {x,y}=node.getBoundingClientRect();return {x,y}}));
 assert(escapeRolls[1].y>escapeRolls[0].y+10);
 assert(Math.abs(escapeRolls[0].x-escapeRolls[1].x)<2,'Alternative rolls align on the right');
 assert(await movementPanel.locator('[data-action-timing="action"]').textContent().then(t=>t.includes('Scattare')));
 assert(await movementPanel.locator('[data-action-timing="movement"]').textContent().then(t=>t.includes('Muoversi')));
 await sheet('info');await sheet('battle');
 assert.equal(await page.locator('#sheet-play-view [data-battle-action="movement"]').getAttribute('open'),'');
 await page.locator('#sheet-play-view [data-act="hp-damage"]').click();await page.locator('#hp-adjust-amount').fill('10');await page.locator('#hp-adjust-confirm').click();
 await page.waitForFunction(()=>document.querySelector('#sheet-play-view [data-read-field="current_hp"]')?.textContent==='37');
 assert.deepEqual([(await record()).temporary_hp,(await record()).second_form_hp,(await record()).current_hp],[0,0,37]);
 const resourcesPanel=page.locator('#sheet-play-view [data-battle-action="resources"]');
 assert.equal(await resourcesPanel.count(),1);
 assert.equal(await resourcesPanel.getAttribute('open'),null,'Risorse starts collapsed');
 assert.equal(await page.locator('.play-health-tools [data-sheet-context="rests"]').count(),1);
 assert.equal((await page.locator('.play-health-tools [data-sheet-context="rests"]').textContent()).trim(),'Riposi');
 assert.equal(await page.locator('.page-head.play-actions-page-title h1').textContent(),'Azioni');
 const variantTitle=page.locator('.page-head [data-act="action-variants"]');
 assert.equal(await variantTitle.count(),1,'Variant rules shortcut is beside the page title');
 assert.equal((await variantTitle.textContent()).trim(),'Varianti alle regole');
 assert.equal(await page.locator('#sheet-play-view [data-act="action-variants"]').count(),0,'No second shortcut inside action groups');
 assert(await variantTitle.isVisible());

 assert.equal(await resourcesPanel.locator('[data-sheet-context="rests"]').count(),0,'Rests belong in HP');
 await resourcesPanel.locator('summary.play-battle-summary').click();
 assert.equal(await resourcesPanel.getAttribute('open'),'');
 const focusResource=resourcesPanel.locator('[data-resource-tracker="focus"] .play-resource-info');
 assert.equal(await focusResource.locator('.play-resource-name').textContent(),'Focus arcano');
 assert.equal(await focusResource.locator('.play-resource-recovery').textContent(),'Recupero: riposo breve');
 assert.match(await focusResource.locator('.play-resource-count').textContent(),/5\s*\/\s*7/);
 const resourceWeight=await focusResource.locator('.play-resource-name').evaluate(node=>Number(getComputedStyle(node).fontWeight));
 const abilityWeight=await resourcesPanel.locator('.play-resource-power-open strong').first().evaluate(node=>Number(getComputedStyle(node).fontWeight));
 assert(resourceWeight>abilityWeight,'Resource name has stronger emphasis than its abilities');
 const inlineClass=resourcesPanel.locator('.play-resource-power-row[data-ability-id="arcane_pulse"]');
 assert.equal(await inlineClass.count(),1,'Class abilities appear beneath their resource');
 assert.equal(await inlineClass.locator('[data-act="battle-use-ability"]').count(),1);
 assert.equal(await resourcesPanel.locator('.play-resource>[data-act="tracker-more"]').count(),0,'No minus shortcut next to tracker');
 assert(!String(await inlineClass.textContent()).includes('Focus arcano'));
 assert(!String(await inlineClass.textContent()).includes(' / '));
 await inlineClass.locator('[data-act="sheet-context"]').click();
 assert.match(await page.locator('#sheet-context-dialog .sheet-context-body').textContent(),/Attiva un impulso magico/);
 assert.match(await page.locator('#sheet-context-dialog .sheet-context-body').textContent(),/Origine[\s\S]*Attivazione[\s\S]*Costo/);
 assert.equal(await page.locator('#sheet-context-dialog [data-act="power-trait"]').count(),1);
 await dismiss();
 assert.equal(await resourcesPanel.locator('[data-ability-resource="free"] .play-resource-heading').textContent(),'Nessun costo');
 assert.equal(await resourcesPanel.locator('[data-ability-resource="free"] .play-resource-power-row[data-ability-id="free_pulse"]').count(),1);
 assert.match(await resourcesPanel.locator('[data-ability-resource="free"]').textContent(),/Azioni gratuite/);
 assert(await resourcesPanel.locator('[data-ability-resource="free"] .play-resource-free-actions [data-attack-id]').count()>0);
 const linkedSpell=resourcesPanel.locator('[data-power-spell-id="arcane_light"]');
 assert.equal(await linkedSpell.count(),1,'Tracker-paid spells belong under their resource');
 assert.equal(await linkedSpell.locator('[data-act="battle-cast-resource-spell"]').count(),1,'Dedicated Lancia button is beside the spell details');
 assert.match(await linkedSpell.textContent(),/Azione/);
 assert.doesNotMatch(await linkedSpell.textContent(),/Incantesimo/);
 await linkedSpell.locator('[data-act="power-spell"]').click();
 assert.match(await page.locator('#action-cast-dialog').textContent(),/Light/);
 await page.locator('#action-cast-dialog [data-act="action-cast-cancel"]').first().click();
 assert.equal(await resourcesPanel.locator('[data-ability-resource="free"] [data-ability-id="arcane_pulse"]').count(),0);
 const focusButton=resourcesPanel.locator('[data-sheet-context="power-resource:tracker:focus"]');
 await focusButton.click();
 assert.match(await page.locator('#sheet-context-dialog .sheet-context-body').textContent(),/Focus arcano|Utilizzi disponibili/);
 assert.equal(await page.locator('#sheet-context-dialog [data-magic-tracker-id="focus"]').count(),1);
 await dismiss();
 const maneuver=resourcesPanel.locator('[data-sheet-context="power-ability:ability:maneuver:phb:commander\'s_strike"]');
 assert.equal(await maneuver.count(),1,'Activated maneuvers should be visible under resources');
 assert.equal(await resourcesPanel.locator('.play-resource-power-row[data-ability-id="activated:ability:maneuver:phb:commander\'s_strike"]').count(),1,'Optional maneuver has its Use button');
 await maneuver.click();
 assert.match(await page.locator('#sheet-context-dialog .sheet-context-body').textContent(),/Commander.s Strike|Costo/);
 await dismiss();
 await focusButton.click();
 await page.locator('#sheet-context-dialog [data-act="tracker-more"][data-tracker-id="focus"]').click();
 await dismiss();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus===3;});
 await resourcesPanel.locator('.play-resource-power-row[data-ability-id="arcane_pulse"] [data-act="battle-use-ability"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus===5;});
 await resourcesPanel.locator('[data-power-spell-id="arcane_light"] [data-act="battle-cast-resource-spell"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus===6;});
 assert.equal(await page.locator('#action-cast-dialog').count(),0,'Quick Lancia casts without opening spell description');
 await focusButton.click();
 assert.equal(await page.locator('#sheet-context-dialog [data-act="tracker-reset"][data-tracker-id="focus"]').count(),1);
 await page.locator('#sheet-context-dialog [data-act="tracker-reset"][data-tracker-id="focus"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return !(await listCreatures())[0].creature.resource_tracker_spent?.focus;});
 await dismiss();
 const speedCard=page.locator('#sheet-play-view [data-sheet-context="movement"]');
 assert.equal(await speedCard.locator('.vtt-action-glyph--pack-1.vtt-action-glyph--slot-9').count(),1,'Movement dash icon');
 assert.equal(await movementPanel.locator('summary.play-battle-summary .vtt-action-glyph--pack-1.vtt-action-glyph--slot-9').count(),1);
 assert.match(await speedCard.textContent(),/Camminata/);
 await popup('movement');assert.match(await page.locator('#sheet-context-dialog .sheet-context-body').textContent(),/Salti|Camminata/);await dismiss();
 await popup('defense');
 const shared=page.locator('#sheet-context-dialog .equipment-unified-panel');
 assert.equal(await shared.count(),1);
 assert.match(await shared.textContent(),/Formula CA naturale/);
 assert.match(await shared.textContent(),/CA totale/);
 assert.equal(await shared.locator('[data-equip-slot]').count(),3);
 const weaponsGroup=shared.locator('.equipment-weapons');
 const armorGroup=shared.locator('.equipment-armor');
 assert.equal(await weaponsGroup.locator('[data-equip-slot]').count(),2);
 assert.equal(await armorGroup.locator('[data-equip-slot="body"]').count(),1);
 assert.equal(await weaponsGroup.locator('[data-field="attack_ability"] option').count(),6);
 assert.equal(await weaponsGroup.locator('[data-field="two_weapon_fighting"]').count(),0,
   'The two-weapon fighting style is not toggled manually');
 assert.equal(await armorGroup.locator('.battle-ac-manage').count(),1);
 assert.equal(await shared.locator('[data-field="hand_grip_two_handed"]').count(),1,
   'Versatile grip is offered for an equipped main-hand versatile weapon');
 assert.equal(await shared.locator('[data-field="attack_ability_finesse_only"]').count(),1);
 for(const width of [320,390]){
  await page.setViewportSize({width,height:844});
  const aligned=await weaponsGroup.locator('.equipment-attack-options').evaluate(node=>{
   const [ability,finesse,grip]=[...node.querySelectorAll(':scope > label')].map(label=>label.getBoundingClientRect());
   return ability.right<=finesse.left+5&&finesse.right<=grip.left+5&&
     Math.abs(ability.top-finesse.top)<24&&Math.abs(ability.top-grip.top)<24;
  });
  assert(aligned,'Attack ability and both options share one horizontal row at '+width+'px');
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),
    'Equipment popup must not overflow at '+width+'px');
 }
 await page.setViewportSize({width:390,height:844});
 assert.doesNotMatch(await shared.textContent(),/Iniziativa/);
 assert.equal(await page.locator('#sheet-context-dialog footer,#sheet-context-dialog .formula-bonus,#sheet-context-dialog .hint').count(),0);
 assert.equal(await shared.locator('.battle-ac-manage').count(),1);
 await dismiss();
 await popup('equipment');
 assert.equal(await page.locator('#sheet-context-dialog .equipment-unified-panel [data-equip-slot]').count(),3);
 await page.locator('#sheet-context-dialog [data-field="attack_ability"]').selectOption('wis');
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.attack_ability==='wis';});
 await page.locator('#sheet-context-dialog [data-field="attack_ability_finesse_only"]').uncheck();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.attack_ability_finesse_only===false;});
 await page.locator('#sheet-context-dialog [data-field="hand_grip_two_handed"]').check();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.hand_grip_two_handed===true;});
 const secondary=page.locator('#sheet-context-dialog .equipment-weapons [data-equip-slot="off"]');
 // Persistence can finish before the equipment popup has rerendered.
 await page.waitForFunction(()=>document.querySelector('#sheet-context-dialog .equipment-weapons [data-equip-slot="off"]')?.disabled===true);
 assert.equal(await secondary.isDisabled(),true,'Versatile grip must disable offhand equipment');
 assert.equal(await secondary.inputValue(),'-1','Versatile grip must lock the offhand on Nessuno');
 assert.equal(await page.locator('#sheet-context-dialog .equipment-unified-panel').count(),1);
 await dismiss();
 await page.locator('#sheet-play-view [data-target="initiative"]').click();
 assert.equal(await page.locator('#sheet-roll-dialog .sheet-roll-provenance').count(),0);
 assert.equal(await page.locator('#sheet-roll-dialog [data-roll-chat-status]:visible').count(),0);
 await page.locator('#sheet-roll-dialog [data-act="close-sheet-roll"]').click();
 await popup('rests');
 const shortRestDice=page.locator('#sheet-context-dialog [data-rest-die="6"]');
 assert.equal(await shortRestDice.count(),1,'Wizard Hit Dice appear in the resting popup');
 await shortRestDice.fill('2');
 await page.locator('#sheet-context-dialog [data-act="tracker-short"]').click();
 await dismiss();
 const afterShort=await record();
 assert.equal(afterShort.resource_tracker_spent.focus,undefined);
 assert.equal(afterShort.hit_dice_spent.d6,2,'Short rest saves spent Hit Dice');
 assert(afterShort.current_hp>=37,'Short rest heals without exceeding maximum');
 await popup('rests');
 assert.equal(await page.locator('#sheet-context-dialog [data-rest-die="6"]').getAttribute('max'),'3');
 await page.locator('#sheet-context-dialog [data-act="tracker-long"]').click();
 await dismiss();
 const afterLong=await record();
 assert.equal(afterLong.temporary_hp,0,'Long rest expires temporary HP');
 assert.equal(afterLong.hit_dice_spent.d6,undefined,'2014 long rest restores half of five Hit Dice');
 assert.equal(afterLong.pact_slots_spent,0);
 assert.deepEqual(afterLong.spell_slots_spent,Array(10).fill(0));
 assert(afterLong.current_hp>=afterShort.current_hp,'Long rest restores maximum HP');
 await sheet('info');
 assert.equal(await page.locator('#sheet-play-view .play-abilities .play-ability').count(),6);
 await popup('tools');
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/Armi/);
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/Armature/);
 await dismiss();
 await page.locator('[data-play-search]').fill('furt');assert.equal(await page.locator('.play-skills [data-play-filter]:visible').count(),1);
 await page.locator('#sheet-play-view [data-target="skill:stealth"]').click();await page.locator('[data-act="roll-sheet-confirm"]').click();assert(Number(await page.locator('.dice-result').textContent())>0);await page.locator('[data-act="close-sheet-roll"]').click();
 await sheet('inventory');
 await popup('equipment');
 assert.equal(await page.locator('#sheet-context-dialog .equipment-unified-panel [data-equip-slot]').count(),3);
 assert.equal(await page.locator('#sheet-context-dialog [data-field="hand_grip_two_handed"]').isChecked(),true);
 assert.equal(await page.locator('#sheet-context-dialog [data-field="attack_ability_finesse_only"]').isChecked(),false);
 assert.match(await page.locator('#sheet-context-dialog .battle-ac-formula').textContent(),/Formula CA naturale/);
 await page.locator('#sheet-context-dialog [data-field="hand_grip_two_handed"]').uncheck();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.hand_grip_two_handed===false;});
 await dismiss();
 await page.locator('[data-play-search]').fill('pozione');await popup('item:1');await page.locator('#sheet-context-dialog [data-item-key="quantity"]').fill('5');await dismiss();assert.equal((await record()).inventory[1].quantity,5);assert.match(await page.locator('#sheet-play-view [data-sheet-context="item:1"]').textContent(),/×5/);
 assert.equal(await page.locator('[data-play-search]').inputValue(),'pozione');assert.equal(await page.locator('#sheet-play-view [data-play-filter]:visible').count(),1);await page.locator('[data-play-search]').fill('');
 await popup('item:0');assert(await page.locator('#sheet-context-dialog .inventory-description').isVisible());await shot('item-popup');await dismiss();
 const inlineCoins=page.locator('#sheet-play-view .inventory-play-coins');
 assert.equal(await inlineCoins.count(),1,'Coin editor must be visible in the shortcut row');
 assert.equal(await inlineCoins.locator('[data-coin-code]').count(),5,'All five denominations must be editable inline');
 assert.equal(await page.locator('#sheet-play-view [data-sheet-context="coins"]').count(),0,'No coin popup trigger');
 assert.equal(await page.locator('#sheet-context-dialog').count(),0,'Editing coins must not open a dialog');
 await inlineCoins.locator('[data-coin-code="gp"]').fill('12');
 await inlineCoins.locator('[data-coin-code="gp"]').press('Tab');
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.coins?.gp===12;});
 await page.waitForFunction(()=>document.querySelector('#sheet-play-view .inventory-play-coins .inventory-coin-total')?.textContent.includes('12 mo'));
 assert.match(await inlineCoins.locator('.inventory-coin-total').textContent(),/12 mo/);
 assert.equal(await page.locator('#sheet-context-dialog').count(),0,'Saving coins must stay on the page');
 await page.locator('#sheet-play-view [data-act="inventory-subtab"][data-subtab="documents"]').click();
 assert.equal(await page.locator('#sheet-play-view [data-sheet-context="item:1"]').count(),0,'Objects must not leak into Documents');
 await popup('inventory-add');await page.locator('#sheet-context-dialog [data-act="document-add"]').click();await page.locator('#sheet-context-dialog .document-edit > summary').click();await page.locator('#sheet-context-dialog [data-document-part="title"]').fill('Lettera della Luna');await page.locator('#sheet-context-dialog [data-document-part="body"]').fill('Raggiungete il tempio al tramonto.');await dismiss();
 assert(await page.locator('#sheet-play-view').textContent().then(t=>t.includes('Lettera della Luna')));
 await sheet('conditions');assert.match(await page.locator('#sheet-play-view').textContent(),/Avvelenato/);assert.match(await page.locator('#sheet-play-view').textContent(),/Livello 2/);await popup('conditions');await page.locator('#sheet-context-dialog [data-condition="poisoned"]').uncheck();await dismiss();assert.equal((await record()).conditions.includes('poisoned'),false);
 await popup('apply-spell');await page.locator('#condition-spell-picker').selectOption('phb2014_light');await page.locator('#sheet-context-dialog [data-act="condition-add-spell"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.proficiency_origins?.some(r=>r.id==='spell:phb2014_light'&&r.applied===true);});
 await page.waitForFunction(()=>/Incantesimi applicati[\s\S]*Light/.test(document.querySelector('#sheet-play-view')?.textContent||''));
 assert.match(await page.locator('#sheet-play-view').textContent(),/Incantesimi applicati[\s\S]*Light/);
 await sheet('battle');assert.match(await page.locator('.play-status-strip').textContent(),/Light/);
 await sheet('conditions');await page.locator('[data-act="condition-remove-spell"][data-spell-id="phb2014_light"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return !(await listCreatures())[0].creature.proficiency_origins?.some(r=>r.id==='spell:phb2014_light');});
 await sheet('magic');
 assert.equal(await page.locator('.magic-ability-entry').count(),0,'Additional nonspell abilities no longer belong in Poteri');
 await popup('magic-tools');assert.equal(await page.locator('#sheet-context-dialog .magic-toolbar button:visible').count(),6);await page.locator('#sheet-context-dialog [data-magic-tool="slots"]').click();await page.locator('#magic-tools-dialog').waitFor();assert.equal(await page.locator('#sheet-context-dialog').count(),0);await page.locator('[data-act="magic-tool-close"]').click();
 await sheet('info');assert.equal(await page.locator('#sheet-play-view [data-sheet-context="trait-notes"]').count(),0);
 assert.equal(await page.locator('.play-info-traits').count(),1);
 assert(await page.locator('.play-info-traits .trait-origin-group').count()>0);
 // All primary context links must resolve on populated and empty sections.
 for(const key of ['info','battle','inventory','conditions']){
  await sheet(key);const keys=await page.locator('#sheet-play-view [data-sheet-context]:visible').evaluateAll(nodes=>nodes.map(n=>n.dataset.sheetContext));
  for(const contextKey of keys){
   try{
    await popup(contextKey);
    assert(await page.locator('.sheet-context-body').textContent().then(t=>t.trim().length>0),key+': '+contextKey);
    await dismiss();
   }catch(error){throw Error('Popup non raggiungibile · '+key+' · '+contextKey+' · '+error.message);}
  }
 }
 await sheet('battle');
 assert(await page.locator('#sheet-play-view [data-battle-action="movement"]').evaluate(node=>
  Boolean(node.compareDocumentPosition(document.querySelector('#sheet-play-view [data-battle-action="checks"]'))&Node.DOCUMENT_POSITION_FOLLOWING)),
  'Spostamento is rendered before Prove abilità');
 const checks=page.locator('#sheet-play-view [data-battle-action="checks"]');
 await checks.locator('summary.play-battle-summary').click();
 assert.equal(await checks.locator('[data-action-ability]').count(),6);
 assert.equal(await checks.locator('.play-battle-attack-entry').count(),24);
 const strength=checks.locator('[data-action-ability="str"]');
 assert.equal(await strength.locator('.play-battle-attack-entry').first().getAttribute('data-attack-id'),'ability_mod:str');
 assert.equal(await strength.locator('[data-target="skill:athletics"]').count(),1);
 assert.equal(await checks.locator('[data-action-ability="con"] .play-battle-attack-entry').count(),1);
 const firstRoll=strength.locator('[data-target="ability_mod:str"]');
 await firstRoll.click();
 assert.match(await page.locator('#sheet-roll-dialog [data-roll-formula]').textContent(),/1d20/);
 await page.locator('#sheet-roll-dialog [data-act="close-sheet-roll"]').click();
 await strength.locator('summary.play-battle-action-heading').click();
 assert.equal(await strength.getAttribute('open'),null);
 await page.locator('.page-head [data-act="action-variants"]').click();
 assert.equal(await page.locator('.variant-list input[type=checkbox]').count(),78);
 await page.locator('[data-close-variants]').click();
 await shot('action-ability-checks');
 // A persistent class feature must expose a reversible action, not an inert "Attiva" badge.
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const row=(await listCreatures())[0],c=row.creature;
  await saveCreature({...c,class:'Barbarian',class_source:'PHB',
   classes:[{name:'Barbarian',source:'PHB',level:5}],level:5,
   active_class_features:{rage:{name:'Ira',origin_id:'class_feature:rage',rules_version:'2014'}}},'default',row.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');
 const ragePanel=page.locator('#sheet-play-view [data-battle-action="resources"]');
 await ragePanel.locator('summary.play-battle-summary').click();
 const rage=ragePanel.locator('.play-resource-power-row').filter({has:page.locator('[data-act="condition-remove-ability"][data-ability-key="rage"]')});
 assert.equal(await rage.count(),1,'Rage has a single Disattiva button when active');
 await rage.locator('[data-act="condition-remove-ability"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return !(await listCreatures())[0].creature.active_class_features?.rage;});
 await ragePanel.locator('[data-act="condition-remove-ability"][data-ability-key="rage"]').waitFor({state:'detached'});
 await ragePanel.locator('[data-act="battle-use-ability"][aria-label^="Attiva Ira"]').waitFor({state:'visible'});
 await page.waitForFunction(()=>!!navigator.serviceWorker.controller,null,{timeout:30000});await context.setOffline(true);await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');await page.locator('#sheet-play-view [data-act="inventory-subtab"][data-subtab="documents"]').click();await page.waitForFunction(()=>document.querySelector('#sheet-play-view')?.textContent.includes('Lettera della Luna'));assert.match(await page.locator('#sheet-play-view').textContent(),/Lettera della Luna/);
 assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);assert.deepEqual(writes,[]);
 console.log('PASS: 7 play sheets at 320/360/390/430px and landscape, contextual editing, HP, tracker recovery, skills, inventory descriptions/quantity, documents, conditions, spell tools, every context link and offline persistence.');
}finally{await f.close();}
