import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';
const f=await browserFixture({live:true});const {page,context,origin,errors,missing,writes,sheet,popup,dismiss,shot}=f;
let seededCreatureId='';
const record=()=>page.evaluate(async id=>{
 const {loadCreature}=await import('/creatures.js');
 return (await loadCreature(id)).data;
},seededCreatureId);
try{
 await seedPlayCreature(page,origin);
 seededCreatureId=await page.evaluate(async()=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures()).find(row=>row.creature.name==='Lyria delle Stelle')?.creature.id||'';
 });
 assert.ok(seededCreatureId,'Fixture character ID required for stable tests');
 // The same optional maneuver used by Poteri must now appear only in battle resources.
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const row=(await listCreatures())[0],creature=row.creature;
  await saveCreature({...creature,
   proficiency_choices:[...(creature.proficiency_choices||[]),
     {kind:'skill',key:'arcana'}, {kind:'expertise',key:'stealth'}],
   resource_trackers:[...(creature.resource_trackers||[]),
     {id:'superiority',name:'Superiority Die',max:4,recharge:'short_rest'}],
   dice_bonuses:[...(creature.dice_bonuses||[]),
     {id:'charge-damage',target:'attack_damage:item:local_sword',dice:'1d6',
      damage_type:'L',origin_name:'Carica fulmine',tracker_id:'focus',tracker_cost:1},
     {id:'charge-hit',target:'attack_roll',dice:'1d4',
      origin_name:'Precisione arcana',tracker_id:'focus',tracker_cost:1}],
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
  for(const key of ['info','battle','magic','inventory','conditions']){
   await sheet(key);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),key+' overflow at '+viewport.width);
   const inlineEditors=page.locator('#sheet-play-view input:not([type=search]):visible,#sheet-play-view select:visible,#sheet-play-view textarea:visible');
   if(key==='magic'){
    const castingEditors=page.locator('#sheet-play-view select[data-casting-section]:visible');
    assert.ok(await castingEditors.count()>=1,'The class spellcasting ability remains editable');
    assert.equal(await inlineEditors.count(),await castingEditors.count(),
      'Only casting abilities, including visible granting origins, are editable inline');
   }else{
    assert.equal(await inlineEditors.count(),key==='inventory'?5:0,
      'Only inventory coin amounts are editable outside spellcasting: '+key);
   }
   if(key==='magic'){
    const classSource=page.locator('#sheet-play-view .play-magic-class-card:not(.play-magic-granted-card)').first();
    const slotLabel=classSource.locator('.play-card-head .play-magic-source-resources');
    assert.equal((await slotLabel.locator('.play-magic-source-resource').first().textContent()).trim(),'Slot',
      'Class spellcasting header exposes one Slot label, with the rest interval separately');
    assert.match(await slotLabel.textContent(),/Riposo lungo/,
      'The current power source documents when spell preparation can change');
    assert.equal(await slotLabel.locator('.play-magic-source-resource').count(),2,
      'Slot and its preparation-rest label are distinct single badges');
    const grantedCard=page.locator('#sheet-play-view .play-magic-granted-card[data-magic-origin-tracker="focus"]');
    assert.equal(await grantedCard.count(),1,'Granted spells have their own visible source card');
    const trackerHeader=grantedCard.locator('.play-card-head [data-play-magic-tracker="focus"]');
    assert(await trackerHeader.isVisible(),'Linked tracker is visible beside the granting origin title');
    assert.match(await trackerHeader.textContent(),/Focus arcano\s*\d+\s*\/\s*\d+/,
      'The granting origin header displays the real shared tracker name and usage');
    const castingRows=page.locator('#sheet-play-view .play-magic-inline-casting .casting-statistics');
    assert.ok(await castingRows.count()>=1,
      'Spellcasting editors remain available for classes and visible granting origins');
    assert.equal(await page.locator('#sheet-play-view [data-sheet-context^="casting:"]').count(),0,
      'No casting settings gear remains');
    assert.equal(await page.locator('#sheet-play-view .play-magic-inline-casting .sheet-result').count(),
      2*await castingRows.count(),
      'Every casting source keeps interactive DC and spell attack calculations');
    assert.equal(await page.locator('#sheet-play-view .play-magic-inline-casting .magic-source-known,.play-magic-inline-casting .magic-source-overview').count(),0,
      'No redundant known-spells summary or nested casting box');
    const castingRow=castingRows.first();
    const controls=castingRow.locator(':scope > label,:scope > span');
    assert.equal(await controls.count(),3,'Characteristic, DC and attack share one row');
    const boxes=await controls.evaluateAll(nodes=>nodes.map(node=>{
      const r=node.getBoundingClientRect();return {left:r.left,right:r.right,cy:r.top+r.height/2};
    }));
    assert(boxes[0].right<=boxes[1].left+1 && boxes[1].right<=boxes[2].left+1,
      'Casting controls are arranged horizontally at '+viewport.width+'px');
    assert(Math.max(...boxes.map(b=>b.cy))-Math.min(...boxes.map(b=>b.cy))<8,
      'Casting controls share a vertical centerline at '+viewport.width+'px');
    const style=await castingRow.evaluate(row=>{
      const select=row.querySelector('select');
      const metric=row.querySelector('.casting-stat--dc .sheet-result');
      return {
        height:select?.getBoundingClientRect().height,
        minHeight:getComputedStyle(select).minHeight,
        computedHeight:getComputedStyle(select).height,
        direction:getComputedStyle(select.parentElement).flexDirection,
        selected:select?.selectedOptions?.[0]?.textContent,
        textSize:parseFloat(getComputedStyle(metric).fontSize),
        border:getComputedStyle(row).borderTopWidth,
        background:getComputedStyle(row).backgroundColor,
        labels:[...row.querySelectorAll('.casting-stat-label')].map(e=>e.textContent.trim())
      };
    });
    assert.equal(style.direction,'row','Casting ability label must not inherit the global vertical label layout');
    assert(style.height>=34&&style.height<=40,'Native ability selector is compact: '+JSON.stringify(style));
    assert.match(style.selected||'',/^(FOR|DES|COS|INT|SAG|CAR)$/);
    assert(style.textSize>=14,'Spell DC must be comfortably readable');
    assert.equal(style.border,'0px','No separate bordered casting box');
    assert.deepEqual(style.labels,['Caratt.','CD','Att.']);
    const actionButtons=page.locator('#sheet-play-view .play-magic-class-card .play-magic-selection>.play-button');
    if(await actionButtons.count()===2){
      const ys=await actionButtons.evaluateAll(nodes=>nodes.map(node=>Math.round(node.getBoundingClientRect().top)));
      assert.equal(ys[0],ys[1],'Prepare and learn buttons share the same row at '+viewport.width+'px');
    }
   }
   if(key==='inventory')assert.equal(await page.locator('#sheet-play-view .inventory-play-coins input[data-coin-code]').count(),5,
     'Visible direct inventory editors must be the five currency inputs');
   if(viewport.width===390)await shot(key);
  }
 }
 await page.setViewportSize({width:390,height:844});
 await sheet('info');
 assert.equal(await page.locator('#sheet-play-view .play-identity [data-sheet-context="identity"]').count(),0,'No separate identity gear');
 assert.equal(await page.locator('#sheet-play-view [data-act="info-portrait-pick"]').count(),0,'Portrait actions belong to the identity dialog');
 assert.equal(await page.locator('#sheet-play-view .play-passives').count(),1,'Alignment and edition replace the portrait action');
 await popup('identity');
 assert.equal(await page.locator('#sheet-context-dialog [data-act="info-portrait-pick"]').count(),1);
 const canonicalName=page.locator('#sheet-context-dialog [data-identity-value="names"]').first();
 await canonicalName.fill('Lyria, guardiana della Luna');
 // Commit on blur before closing the modal, avoiding an input/change/Escape race.
 await canonicalName.press('Tab');
 await page.waitForFunction(async()=>{
   const {listCreatures}=await import('/creatures.js');
   return (await listCreatures())[0]?.creature?.name==='Lyria, guardiana della Luna';
 });
 await page.keyboard.press('Escape');await page.locator('#sheet-context-dialog').waitFor({state:'detached'});
 // Persistence and rerender finish asynchronously after the dialog dismisses.
 await page.waitForFunction(async()=>{
   const {listCreatures}=await import('/creatures.js');
   return (await listCreatures())[0]?.creature?.name==='Lyria, guardiana della Luna';
 });
 assert.equal((await record()).name,'Lyria, guardiana della Luna');assert.match(await page.locator('.play-identity h2').textContent(),/guardiana/);
 await popup('identity');
 await page.locator('#sheet-context-dialog [data-identity-kind="names"]').click();
 const newName=page.locator('#sheet-context-dialog [data-identity-value="names"]').last();
 assert.equal(await newName.evaluate(node=>document.activeElement===node),true,'New name receives focus');
 await newName.fill('Lyria delle Due Lune');await newName.press('Tab');
 await page.locator('#sheet-context-dialog [data-identity-active="names"]').last().check();
 await page.waitForFunction(async()=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0]?.creature?.name==='Lyria delle Due Lune';
 });
 assert.equal(await page.locator('#sheet-context-dialog [data-identity-active="names"]:checked').count(),1);
 await page.locator('#sheet-context-dialog [data-identity-active="names"]').first().check();
 await page.locator('#sheet-context-dialog [data-identity-kind="factions"]').click();
 const factionInput=page.locator('#sheet-context-dialog [data-identity-value="factions"]').last();
 assert.equal(await factionInput.evaluate(node=>document.activeElement===node),true,'New faction receives focus');
 await factionInput.fill('Gilda degli Arcani');await factionInput.press('Tab');
 await page.locator('#sheet-context-dialog [data-identity-active="factions"]').last().check();
 await page.locator('#sheet-context-dialog [data-identity-kind="factions"]').click();
 await page.locator('#sheet-context-dialog [data-identity-value="factions"]').last().fill('Compagnia della Stella');
 await page.locator('#sheet-context-dialog [data-identity-value="factions"]').last().press('Tab');
 await page.locator('#sheet-context-dialog [data-identity-active="factions"]').last().check();
 await page.locator('#sheet-context-dialog [data-identity-kind="factions"]').click();
 await page.locator('#sheet-context-dialog [data-identity-value="factions"]').last().press('Tab');
 assert.equal(await page.locator('#sheet-context-dialog [data-identity-value="factions"]').count(),3,'Blank faction entry disappears, preserving default Party');
 await dismiss();
 assert.equal((await record()).identity_names.length,2);
 assert.deepEqual((await record()).identity_factions.filter(row=>row.active).map(row=>row.value),['Party','Gilda degli Arcani','Compagnia della Stella']);
 assert.equal((await record()).name,'Lyria, guardiana della Luna');
 await sheet('info');
 assert.equal(await page.locator('[data-act="edit-bonus"], .formula-bonus').count(),0,
   'No legacy ± navigation remains anywhere in the rendered sheet');
 assert.equal(await page.locator('#sheet-play-view .play-competences .play-section-divider').count(),0,'Redundant Competenze heading is removed');
 assert.equal(await page.locator('#sheet-play-view .play-competence-tools').count(),0,'Redundant Altre competenze action is removed');
 assert.equal(await page.locator('#sheet-play-view .play-quickstat').count(),0,'Quickstats live in Actions only');
 await sheet('battle');
 const competenceButton=page.locator('#sheet-play-view .play-quickstat[data-act="battle-competences-open"]');
 assert.equal(await competenceButton.count(),1,'Competenze opens the existing complete proficiency summary');
 assert.equal(await competenceButton.locator('.vtt-action-glyph--pack-3.vtt-action-glyph--slot-0').count(),1);
 await competenceButton.click();
 const competenceDialog=page.locator('#sheet-context-dialog');
 assert(await competenceDialog.isVisible());
 assert.match(await competenceDialog.textContent(),/Altre competenze/);
 await competenceDialog.locator('[data-act="sheet-context-close"]').click();
 await competenceDialog.waitFor({state:'detached'});
 assert.equal(await page.locator('#sheet-play-view[data-sheet="battle"]').count(),1,'Closing proficiency summary returns to Actions');
 const inspiration=page.locator('#sheet-play-view [data-act="sheet-inspiration-toggle"]');
 assert.equal(await inspiration.count(),1);
 const wasInspired=await inspiration.getAttribute('aria-pressed')==='true';
 await inspiration.click();
 await page.waitForFunction(async expected=>{
   const {listCreatures}=await import('/creatures.js');
   return Boolean((await listCreatures())[0]?.creature?.inspiration)===expected;
 },!wasInspired);
 assert.equal((await record()).inspiration,!wasInspired,'Inspiration is persisted without a popup');
 assert.equal(await page.locator('#sheet-movement-dialog').count(),0,'Legacy movement popup is removed');
 const senses=page.locator('#sheet-play-view [data-act="sheet-senses-open"]');
 assert.equal(await senses.count(),1);
 assert.equal(await senses.locator('.vtt-action-glyph--pack-0.vtt-action-glyph--slot-10').count(),1,'Sensi uses the golden eye icon');
 await senses.click();
 const sensesDialog=page.locator('#sheet-senses-dialog');
 assert(await sensesDialog.isVisible());
 assert.match(await sensesDialog.textContent(),/Luce fioca/);
 await sensesDialog.locator('[data-act="sheet-score-formula"][data-target="passive_perception"]').click();
 const scoreFormula=page.locator('#sheet-score-formula-dialog');
 assert(await scoreFormula.isVisible());
 assert.equal(await scoreFormula.locator('[data-act="sheet-score-edit-base"]').count(),0,
   'Derived passive perception must never expose a base-value editor');
 assert.equal(await scoreFormula.locator('[data-score-formula] .sheet-roll-origin-symbol').first().textContent()
   .then(x=>x.startsWith('10')),true);
 assert.equal(await scoreFormula.locator('[data-roll-mode], [data-act="roll-sheet-confirm"]').count(),0,
   'Computed scores have no dice controls');
 await scoreFormula.locator('[data-act="close-score-formula"]').click();
 await sensesDialog.locator('[data-act="sheet-senses-close"]').click();
 await sheet('info');
 assert.equal(await page.locator('#sheet-play-view .play-ability header [data-act="sheet-proxy"]').count(),0,
   'The six ability edit gears are removed from the info cards');
 await page.locator('#sheet-play-view [data-act="sheet-score-formula"][data-target="ability:str"]').click();
 assert.match(await scoreFormula.locator('h2').textContent(),/Punteggio/);
 assert.equal(await scoreFormula.locator('[data-score-formula]').count(),1);
 assert.equal(await scoreFormula.locator('[data-act="sheet-score-edit-base"]').count(),1,
   'Only the base ability tile opens the new editor');
 await scoreFormula.locator('[data-act="sheet-score-edit-base"]').click();
 const editor=page.locator('#sheet-score-dialog');
 assert.equal(await editor.getAttribute('data-score-target'),'ability:str');
 assert.match(await editor.locator('h2').textContent(),/Modifica valore base/);
 assert.equal(await editor.locator('[data-act="sheet-base-auto-hp"]').count(),0);
 assert.equal(await editor.locator('#sheet-score-input').inputValue(),'12');
 assert.equal(await editor.locator('.sheet-base-editor-save').count(),1);
 assert.equal(await editor.locator('.sheet-base-editor-cancel').count(),1);
 await editor.locator('#sheet-score-input').fill('13');
 await editor.locator('[data-act="save-score"]').click();
 await scoreFormula.waitFor({state:'visible'});
 assert.equal((await record()).abilities.str,13);
 assert.match(await scoreFormula.locator('[data-score-formula] .sheet-roll-origin-value').first().textContent(),/13/);
 await scoreFormula.locator('[data-act="sheet-score-edit-base"]').click();
 await editor.locator('#sheet-score-input').fill('12');
 await editor.locator('[data-act="save-score"]').click();
 await scoreFormula.waitFor({state:'visible'});
 assert.equal((await record()).abilities.str,12);
 await scoreFormula.locator('[data-act="close-score-formula"]').click();
 const skills=page.locator('#sheet-play-view .play-skills-disclosure');
 await skills.locator(':scope > summary').click();
 await skills.locator('[data-target="skill:arcana"]').click();
 const training=page.locator('#sheet-roll-dialog .sheet-roll-origin-term')
   .filter({has:page.locator('.sheet-roll-origin-symbol:text-is("+Mod.Competenza")')});
 assert(await training.count()>=1,'Arcana proficiency must expose a navigable provenance');
 const trainingSource=await training.first().getAttribute('data-origin-id');
 assert(trainingSource&&trainingSource.length>0,'Proficiency cannot be a blank provenance');
 await training.first().click();
 assert.equal(await page.locator('#roll-trait-picker').count(),0,
   'Training provenance must not open the add-bonus picker');
 assert.match(await page.locator('#trait-benefits-dialog h2').textContent(),/Sage/,
   'Navigating the Arcana training term opens the granting background trait');
 await page.locator('#trait-benefits-dialog [data-act="trait-benefits-close"]').click();
 if((await skills.getAttribute('open'))!==null)await skills.locator(':scope > summary').click();
 await sheet('battle');
 const hpCard=page.locator('#sheet-play-view .play-health');
 assert.equal(await hpCard.locator('.play-hp-edit').count(),0,'HP card has no extra edit icon');
 await hpCard.click({position:{x:22,y:80}});
 const hpDialog=page.locator('#hp-adjust-dialog');
 await hpDialog.waitFor({state:'visible'});
 assert.equal(await hpDialog.locator('#hp-adjust-amount').inputValue(),'','Quick HP amount starts empty');
 assert.equal(await hpDialog.locator('#hp-adjust-current').inputValue(),String((await record()).current_hp));
 assert.equal(await hpDialog.locator('#hp-adjust-temporary').inputValue(),'3', 'Seeded temporary HP must appear in dialog');
 assert(await hpDialog.locator('#hp-adjust-current').evaluate(el=>el.getBoundingClientRect().width<170),
   'HP numeric fields remain compact');
 await hpDialog.locator('[data-act="hp-adjust-max"]').click();
 await scoreFormula.waitFor({state:'visible'});
 assert.match(await scoreFormula.locator('h2').textContent(),/PF massimi/);
 assert.equal(await editor.count(),0,'HP maximum opens the formula popup, not the base editor');
 await scoreFormula.locator('[data-act="sheet-score-edit-base"]').click();
 assert.equal(await editor.getAttribute('data-score-target'),'hp');
 assert.equal(await editor.locator('#sheet-score-input').inputValue(),'40');
 const autoHp=editor.locator('[data-act="sheet-base-auto-hp"]');
 assert.equal(await autoHp.count(),1);
 assert(await autoHp.isEnabled(),'Wizard hit dice should be available for automatic HP');
 await autoHp.click();
 const automaticHp=Number(await editor.locator('#sheet-score-input').inputValue());
 assert(Number.isInteger(automaticHp)&&automaticHp>0,'Automatic hit dice prefill the base HP field');
 assert.equal((await record()).max_hp_base,40,'Automatic HP is a preview until saved');
 await editor.locator('.sheet-base-editor-cancel').click();
 await scoreFormula.waitFor({state:'visible'});
 assert.equal((await record()).max_hp_base,40,'Cancel leaves original maximum HP untouched');
 await scoreFormula.locator('[data-act="close-score-formula"]').click();
 await hpDialog.locator('[data-act="hp-adjust-cancel"]').first().click();
 assert.equal(await page.locator('#sheet-play-view [data-act="battle-toggle-class-only"]').count(),0,
  'Obsolete class-only toggle is absent');

 const toolbar=page.locator('#sheet-play-view .play-battle-expansion-tools');
 assert.equal(await toolbar.locator('button').count(),2);
 const activeState=page.locator('#sheet-play-view .play-status-strip');
 assert.equal(await activeState.count(),1);
 assert.equal(await activeState.evaluate(node=>getComputedStyle(node).borderTopStyle),'solid',
  'States display a visible enclosing border');
 for(const width of [320,360,390,430]){
  await page.setViewportSize({width,height:844});
  const buttons=await toolbar.locator('button').evaluateAll(nodes=>
   nodes.map(node=>{const rect=node.getBoundingClientRect();return {top:rect.top,right:rect.right};}));
  assert.equal(buttons.length,2);
  assert(buttons.every(rect=>Math.abs(rect.top-buttons[0].top)<2),
   'Expand and collapse remain on one row at '+width+'px');
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),
   'Single-row action buttons must not overflow at '+width+'px');
 }
 await page.setViewportSize({width:390,height:844});

 assert.equal(await page.locator('#sheet-play-view [data-battle-action="movement"]').count(),0,
   'Empty generic action categories disappear by default');
 const weaponPanel=page.locator('#sheet-play-view [data-battle-action="attacks"]');
 const movementPanel=page.locator('#sheet-play-view [data-battle-action="others"]');
 assert.equal(await weaponPanel.count(),1);assert.equal(await weaponPanel.getAttribute('open'),'');
 assert.match(await weaponPanel.locator('summary.play-battle-summary').textContent(),/Attacchi/);
 const otherPanel=page.locator('#sheet-play-view [data-battle-action="others"]');

 assert.equal(await otherPanel.count(),1);
 assert.equal(await page.locator('#sheet-play-view [data-battle-action="abilities"]').count(),0,'Abilities belong beneath resources');
 assert.match(await otherPanel.locator('summary.play-battle-summary').textContent(),/Azioni/);
 await otherPanel.locator('summary.play-battle-summary').click();
 assert.equal(await otherPanel.locator('.play-battle-action-group:has([data-attack-id="search"])').getAttribute('open'),'',
  'Opening Other Actions automatically expands its action-type subsections');
 const searchAction=otherPanel.locator('[data-attack-id="search"]');
 assert.equal(await searchAction.locator('[data-target="skill:perception"]').count(),1);
 assert.equal(await searchAction.locator('[data-target="skill:investigation"]').count(),1);
 assert.equal(await searchAction.locator('.play-battle-effect').count(),0);
 const alternativeRolls=await searchAction.locator('.play-battle-attack-roll').evaluateAll(nodes=>
   nodes.map(node=>{const {x,y,right}=node.getBoundingClientRect();return {x,y,right}}));
 assert.equal(alternativeRolls.length,2);
 assert(alternativeRolls[1].y>alternativeRolls[0].y+10,'Alternative dice buttons must stack');
 await otherPanel.locator('summary.play-battle-summary').click();
 assert.equal(await page.locator('#sheet-play-view [data-battle-action="spells"]').count(),0,
  'There is no second spell list below skill checks');
 assert.equal(await weaponPanel.locator('.play-chevron').count(),0);
 assert.equal(await page.locator('.play-battle-heading-tools [data-sheet-context="equipment"]').count(),1);
 assert.equal(await page.locator('.play-battle-heading-tools [data-act="action-open-spells"]').count(),0);
 // Spellcasting must open the Powers tab in a single click.
 await otherPanel.locator('summary.play-battle-summary').click();
 const castFromActions=otherPanel.locator('[data-attack-id="spell_cast"] [data-act="action-open-spells"]');
 assert.equal(await castFromActions.count(),1);
 await castFromActions.click();
 await page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='magic');
 await sheet('battle');
 const mainAttack=weaponPanel.locator('[data-attack-id="item:local_sword"]');
 assert.equal(await mainAttack.count(),1);
 assert.equal(await weaponPanel.locator('[data-action-timing]').count(),0,
  'Weapon attacks have no timing subsections');
 const mainTiming=otherPanel.locator('[data-action-timing="action"]');
 assert.equal(await mainTiming.locator('summary.play-battle-action-heading').count(),1);
 if((await otherPanel.getAttribute('open'))===null)
  await otherPanel.locator('summary.play-battle-summary').click();
 assert.equal(await mainTiming.getAttribute('open'),'',
  'Opening Azioni expands all action-time groups');
 await mainTiming.locator('summary.play-battle-action-heading').click();
 assert.equal(await mainTiming.getAttribute('open'),null,'Individual timing groups can close');
 await mainTiming.locator('summary.play-battle-action-heading').click();
 const opportunity=otherPanel.locator('[data-attack-id="opportunity"]');
 assert.match(await opportunity.locator('.play-battle-attack-copy strong').textContent(),/Attacco di opportunità/);
 assert.equal(await opportunity.locator('[data-act="battle-damage-roll"]').count(),0,
  'Opportunity is generic rather than a main-hand weapon attack');
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
 const rollDialog=page.locator('#sheet-roll-dialog');
 // An actual calculated weapon attack must use the characteristic's keyword
 // instead of showing only the numerical modifier.
 assert.equal(await damageButton.getAttribute('data-damage-attack-id'),'item:local_sword');
 await damageButton.click();
 assert.doesNotMatch(await rollDialog.locator('h2').textContent(),/Danni/i,
   'The weapon name alone identifies this damage roll');
 assert.match(await rollDialog.locator('.sheet-roll-origin-symbol').first().textContent(),
   /Mod.FOR/,'Original weapon damage must name its actual attack characteristic');
 assert.equal(await rollDialog.locator('[data-roll-formula] .sheet-roll-origin-term').count(),1);
 await rollDialog.locator('.sheet-roll-close').click();
 // A second synthetic fire damage component gets its own damage-type row.
 await damageButton.evaluate(node=>{
   node.dataset.damageFormula='1d6+3+2d4';
   node.dataset.damageType='slashing;fire';
 });
 await damageButton.click();
 assert.equal(await rollDialog.getAttribute('data-roll-kind'),'damage');
 assert.match(await rollDialog.textContent(),/Lama lunare/);
 assert.equal((await rollDialog.locator('h2').textContent()).includes('Lyria'),false,
   'The popup title must never contain the character name');

 assert.equal(await rollDialog.locator('.sheet-roll-close').count(),1);
 assert.equal(await rollDialog.locator('[data-act="battle-damage-close"]').count(),0);
 assert.equal(await rollDialog.locator('[data-act="sheet-roll-add-bonus"]').count(),1);
 assert.equal(await rollDialog.locator('[data-roll-mode]').isDisabled(),true,
   'Damage rolls must not offer an advantage/disadvantage mechanic');
 assert.equal((await rollDialog.locator('.sheet-roll-math').nth(1).locator('strong').textContent()).trim(),'Tiro per danni');
 assert.deepEqual(await rollDialog.locator('[data-roll-formula] .sheet-roll-origin-damage-type').allTextContents(),
   ['Tagliente','Fuoco']);
 assert.deepEqual(await rollDialog.locator('[data-roll-formula] .sheet-roll-origin-symbol').allTextContents(),
   ['1d6 + Modificatore',' + 2d4']);
 assert.equal(await rollDialog.locator('[data-roll-formula] .sheet-roll-origin-term').count(),2,
   'Base dice and their modifier must stay in the same compact tile');
 assert.match(await rollDialog.locator('[data-roll-formula]').textContent(),/d6/);
 assert(await rollDialog.locator('.sheet-roll-origin-term').first().evaluate(node=>{
   const bounds=node.getBoundingClientRect();
   const dialog=node.closest('#sheet-roll-dialog').getBoundingClientRect();
   return bounds.width<dialog.width-25&&bounds.height<220;
 }),'Damage formula tiles must remain compact and fit within the dialog');
 assert.equal(await rollDialog.locator('[data-roll-add-status]').count(),0);
 assert.equal(await rollDialog.locator('[data-roll-chat-status]').count(),0);
 assert.match(await rollDialog.locator('.sheet-roll-bonuses-head').textContent(),/Bonus applicabili al tiro/);
 assert.equal(await rollDialog.locator('[data-act="sheet-roll-add-applicable"]').count(),1);
 assert.equal(await rollDialog.locator('.sheet-roll-bonus-term').count(),1);
 assert.match(await rollDialog.locator('.sheet-roll-bonus-term').textContent(),/Carica fulmine/);
 assert.match(await rollDialog.locator('[data-act="sheet-roll-open-tracker"]').getAttribute('aria-label'),/5 rim/);
 assert.equal(await rollDialog.locator('.sheet-roll-bonus-term .sheet-roll-bonus-controls').count(),0,
   'Use and tracker controls are outside, not inside, the formula tile');
 assert.equal(await rollDialog.locator('.sheet-roll-bonus-item > .sheet-roll-bonus-controls > button').count(),2);
 assert.equal(await rollDialog.locator('.sheet-roll-bonus-item .sheet-roll-bonus-term').count(),1);
 assert.equal(await rollDialog.locator('.sheet-roll-tracker-open .vtt-action-glyph').count(),1,
   'The crosshair action uses the shared icon set');
 const typography=await rollDialog.evaluate(dialog=>{
   const base=getComputedStyle(dialog.querySelector('.sheet-roll-formula:not(.sheet-roll-applicable)>span'));
   const applied=getComputedStyle(dialog.querySelector('.sheet-roll-bonuses-head>span'));
   return [base.fontSize,base.color,applied.fontSize,applied.color];
 });
 assert.equal(typography[0],typography[2],'Applicable heading matches the formula heading size');
 assert.equal(typography[1],typography[3],'Applicable heading matches the formula heading color');
 const tileStyle=await rollDialog.evaluate(dialog=>{
   const formula=dialog.querySelector('[data-roll-formula]');
   const ordinary=formula.querySelector('.sheet-roll-origin-term:not(.is-base)')||
     formula.querySelector('.sheet-roll-origin-term');
   const base=getComputedStyle(ordinary);
   const applied=getComputedStyle(dialog.querySelector('.sheet-roll-bonus-term'));
   return [base.borderRadius,base.borderTopStyle,base.paddingTop,
     applied.borderRadius,applied.borderTopStyle,applied.paddingTop];
 });
 assert.deepEqual(tileStyle.slice(0,3),tileStyle.slice(3),'Applicable tiles share the formula tile surface');
 for(const width of [320,360,390,430]){
   await page.setViewportSize({width,height:844});
   const bounds=await rollDialog.evaluate(dialog=>{
     const popup=dialog.getBoundingClientRect();
     const area=dialog.querySelector('.sheet-roll-applicable').getBoundingClientRect();
     const head=dialog.querySelector('.sheet-roll-bonuses-head').getBoundingClientRect();
     const list=dialog.querySelector('.sheet-roll-bonus-list').getBoundingClientRect();
     return {popupWidth:popup.width,areaWidth:area.width,
       areaRight:area.right,popupRight:popup.right,headRight:head.right,listRight:list.right,
       tileWidth:dialog.querySelector('.sheet-roll-bonus-term').getBoundingClientRect().width,
       bodyOverflow:document.documentElement.scrollWidth-innerWidth};
   });
   assert(bounds.areaWidth<bounds.popupWidth&&bounds.areaRight<=bounds.popupRight-8,
     'Applicable section fits inside popup at '+width+'px');
   assert(bounds.headRight<=bounds.areaRight+1&&bounds.listRight<=bounds.areaRight+1,
     'Heading and bonus list stay within their own section at '+width+'px');
   assert(bounds.tileWidth>=130&&bounds.bodyOverflow<=1,
     'Tiles remain legible without page overflow at '+width+'px: '+JSON.stringify(bounds));
 }
 await page.setViewportSize({width:390,height:844});
 // A short +1 must not squeeze long origin names into letter-wide columns.
 await rollDialog.evaluate(dialog=>{
   const formula=dialog.querySelector('[data-roll-formula] .sheet-roll-origin-terms');
   const clone=formula.querySelector('.sheet-roll-origin-term').cloneNode(true);
   clone.classList.add('test-long-provenance');
   clone.querySelector('.sheet-roll-origin-symbol').textContent='+1';
   clone.querySelector('.sheet-roll-origin-name').textContent='Stone of Good Luck';
   formula.append(clone);
 });
 const longLabel=rollDialog.locator('.test-long-provenance');
 assert(await longLabel.evaluate(node=>{
   const tile=node.getBoundingClientRect();
   const label=node.querySelector('.sheet-roll-origin-name').getBoundingClientRect();
   return tile.width>=120&&label.width>=100&&label.height<70;
 }),'A Stone of Good Luck +1 tile must stay readable in a few lines');
 await longLabel.evaluate(node=>node.remove());
 assert.equal(await rollDialog.locator('[data-roll-formula] .sheet-roll-origin-damage-type').count(),2);
 await rollDialog.locator('[data-act="sheet-roll-use-bonus"]').click();
 await page.waitForFunction(()=>document.querySelector('#sheet-roll-dialog [data-act="sheet-roll-use-bonus"]')?.textContent==='Usato');
 assert.equal(await rollDialog.locator('[data-act="sheet-roll-use-bonus"]').isDisabled(),true);
 assert.match(await rollDialog.locator('[data-act="sheet-roll-open-tracker"]').getAttribute('aria-label'),/4 rim/);
 assert.deepEqual(await rollDialog.locator('[data-roll-formula] .sheet-roll-origin-damage-type').allTextContents(),
   ['Tagliente','Fuoco','Fulmine']);
 assert.equal(await rollDialog.locator('[data-roll-formula] .sheet-roll-origin-symbol').last().textContent(),'+1d6');
 assert(await rollDialog.locator('[data-roll-formula] .sheet-roll-origin-damage-type').last().evaluate(node=>
   getComputedStyle(node).whiteSpace==='nowrap'&&node.scrollWidth<=node.clientWidth+1));
 await page.waitForFunction(async()=>{
   const {listCreatures}=await import('/creatures.js');
   return (await listCreatures())[0].creature.resource_tracker_spent?.focus===3;
 });
 const layout=async()=>rollDialog.evaluate(dialog=>{
   const mode=dialog.querySelector('[data-roll-mode]').getBoundingClientRect();
   const button=dialog.querySelector('[data-act="roll-sheet-confirm"]').getBoundingClientRect();
   return {modeY:mode.y,buttonY:button.y,modeWidth:mode.width,buttonWidth:button.width};
 });
 const damageLayout=await layout();
 assert(Math.abs(damageLayout.modeY-damageLayout.buttonY)<=25,'Mode and roll action belong on the same row');
 assert(damageLayout.buttonWidth>damageLayout.modeWidth,'Roll action must take most of the width');
 await rollDialog.locator('[data-act="roll-sheet-confirm"]').click();
 assert.equal(await rollDialog.locator('[data-roll-result] p').count(),0);
 assert.equal(await rollDialog.locator('.sheet-roll-die-value').count(),4,
   '1d6 base + 2d4 damage + 1d6 bonus show four individual die results');
 await page.waitForFunction(async()=>{
   const {listCreatures}=await import('/creatures.js');
   return (await listCreatures())[0].creature.resource_tracker_spent?.focus===3;
 });
 assert.equal(await rollDialog.locator('[data-act="roll-sheet-confirm"]').isVisible(),true,
   'Roll action stays visible after damage roll');
 assert(await rollDialog.evaluate(dialog=>{
   const result=dialog.querySelector('[data-roll-result]').getBoundingClientRect();
   const actions=dialog.querySelector('.sheet-roll-actions').getBoundingClientRect();
   return actions.top>=result.bottom;
 }),'Roll controls stay below damage results');
 await rollDialog.locator('[data-act="roll-sheet-confirm"]').click();
 assert.equal(await rollDialog.locator('[data-roll-result]').isVisible(),true,'Reroll stays possible');
 await page.waitForFunction(async()=>{
   const {listCreatures}=await import('/creatures.js');
   return (await listCreatures())[0].creature.resource_tracker_spent?.focus===3;
 });
 await rollDialog.locator('.sheet-roll-close').click();
 await mainAttack.locator('[data-target="attack_hit:item:local_sword"]').click();
 assert.equal(await mainAttack.locator('details').getAttribute('open'),null,'Dice trigger must not expand description');
 assert.equal(await rollDialog.getAttribute('data-roll-kind'),'d20');
 assert.match(await rollDialog.locator('[data-roll-formula]').textContent(),/1d20/);
 assert.doesNotMatch(await rollDialog.locator('h2').textContent(),/Lyria/);
 assert.equal((await rollDialog.locator('.sheet-roll-math').nth(1).locator('strong').textContent()).trim(),
   'Tiro per colpire · Mischia');
 assert.equal(await rollDialog.locator('[data-act="sheet-roll-edit-bonus"]').count(),0);
 assert.equal(await rollDialog.locator('[data-act="sheet-roll-add-bonus"]').count(),1);
 assert.equal(await rollDialog.locator('.sheet-roll-bonus-term').count(),1);
 assert.equal(await rollDialog.locator('[data-roll-mode]').isEnabled(),true);
 // The fixture is Poisoned: its attack disadvantage cancels manually selected advantage.
 await rollDialog.locator('[data-roll-mode]').selectOption('advantage');
 assert.match(await rollDialog.locator('[data-roll-formula]').textContent(),/ADV/);
 assert.match(await rollDialog.locator('[data-roll-formula]').textContent(),/DIS/);
 await rollDialog.locator('[data-act="roll-sheet-confirm"]').click();
 assert.equal(await rollDialog.locator('[data-act="roll-sheet-confirm"]').isVisible(),true);
 assert.doesNotMatch(await rollDialog.locator('[data-roll-result]').textContent(),/d20 · vantaggio/,
   'Poisoned and situational advantage must cancel to a single d20');
 const d20Layout=await layout();
 assert(d20Layout.buttonWidth>d20Layout.modeWidth);
 assert(await rollDialog.evaluate(dialog=>{
   const result=dialog.querySelector('[data-roll-result]').getBoundingClientRect();
   const actions=dialog.querySelector('.sheet-roll-actions').getBoundingClientRect();
   return actions.top>=result.bottom;
 }),'Mode and roll button move below the d20 result');
 await rollDialog.locator('[data-roll-mode]').selectOption('disadvantage');
 await rollDialog.locator('[data-act="roll-sheet-confirm"]').click();
 assert.equal(await rollDialog.locator('.sheet-roll-die-value').count(),2,
   'Disadvantage must show exactly two individual d20 results');
 await rollDialog.locator('[data-roll-mode]').selectOption('normal');
 await rollDialog.locator('[data-act="roll-sheet-confirm"]').click();
 assert.equal(await rollDialog.locator('[data-roll-result]').isVisible(),true);
 await rollDialog.locator('.sheet-roll-close').click();
 if((await movementPanel.getAttribute('open'))!==null)
  await movementPanel.locator('summary.play-battle-summary').click();
 assert.equal(await movementPanel.getAttribute('open'),null);
 await movementPanel.locator('summary.play-battle-summary').click();
 assert.equal(await movementPanel.locator('.play-battle-action-group:has([data-attack-id="escape_grapple"])').getAttribute('open'),'',
  'Movement action-type subsections expand alongside their parent');
 const escapeAction=movementPanel.locator('[data-attack-id="escape_grapple"]');
 assert.equal(await escapeAction.locator('[data-target="skill:athletics"]').count(),1);
 assert.equal(await escapeAction.locator('[data-target="skill:acrobatics"]').count(),1);
 await escapeAction.locator('[data-target="skill:athletics"]').click();
 assert.doesNotMatch(await page.locator('#sheet-roll-dialog h2').textContent(),/Lyria/);
 assert.equal((await page.locator('#sheet-roll-dialog .sheet-roll-math').nth(1).locator('strong').textContent()).trim(),
   'Prova di abilità · Forza');
 await page.locator('#sheet-roll-dialog [data-act="close-sheet-roll"]').click();
 const escapeRolls=await escapeAction.locator('.play-battle-attack-roll').evaluateAll(nodes=>
   nodes.map(node=>{const {x,y}=node.getBoundingClientRect();return {x,y}}));
 assert(escapeRolls[1].y>escapeRolls[0].y+10);
 assert(Math.abs(escapeRolls[0].x-escapeRolls[1].x)<2,'Alternative rolls align on the right');
 assert(await movementPanel.locator('[data-action-timing="action"]').textContent().then(t=>t.includes('Scattare')));
 assert(await movementPanel.locator('[data-action-timing="movement"]').textContent().then(t=>t.includes('Muoversi')));
 await sheet('info');await sheet('battle');
 assert.equal(await page.locator('#sheet-play-view [data-battle-action="others"]').getAttribute('open'),'');
 await hpCard.click({position:{x:22,y:80}});
 await page.locator('#hp-adjust-current').fill('39');
 await page.locator('#hp-adjust-temporary').fill('5');
 await page.waitForFunction(async creatureId=>{
  const {loadCreature}=await import('/creatures.js');
  const creature=(await loadCreature(creatureId))?.data;
  return creature?.current_hp===39&&creature?.temporary_hp===5;
 },seededCreatureId);
 assert.equal((await record()).current_hp,39,'Direct current HP edits are saved');
 assert.equal((await record()).temporary_hp,5,'Temporary HP are editable');
 await page.locator('#hp-adjust-dialog [data-act="hp-adjust-cancel"]').click();
 await hpCard.click({position:{x:22,y:80}});
 assert.equal(await page.locator('#hp-adjust-amount').inputValue(),'','Damage amount starts empty');
 await page.locator('#hp-adjust-amount').fill('7');
 await page.locator('#hp-adjust-dialog [data-hp-mode="damage"]').click();
 await page.waitForFunction(()=>document.querySelector('#sheet-play-view [data-read-field="current_hp"]')?.textContent==='37');
 assert.deepEqual([(await record()).temporary_hp,(await record()).second_form_hp,(await record()).current_hp],[0,4,37],
   'The separate inactive form keeps its HP while damage consumes temporary and current HP');
 // Healing uses the same editor and caps at the computed maximum.
 await hpCard.click({position:{x:22,y:80}});
 await page.locator('#hp-adjust-amount').fill('3');
 await page.locator('#hp-adjust-dialog [data-hp-mode="heal"]').click();
 await page.waitForFunction(async creatureId=>{
  const {loadCreature}=await import('/creatures.js');
  return (await loadCreature(creatureId)).data.current_hp===40;
 },seededCreatureId);
 const healedHp=(await record()).current_hp;
 const maximumHp=Number((await page.locator('#sheet-play-view [data-calculated="hp"]').first().textContent()).trim());
 assert.equal(healedHp,Math.min(maximumHp,40),'Healing cannot exceed maximum HP');
 if(healedHp>37){
  await hpCard.click({position:{x:22,y:80}});
  await page.locator('#hp-adjust-amount').fill(String(healedHp-37));
  await page.locator('#hp-adjust-dialog [data-hp-mode="damage"]').click();
  await page.waitForFunction(async creatureId=>{
   const {loadCreature}=await import('/creatures.js');
   return (await loadCreature(creatureId)).data.current_hp===37;
  },seededCreatureId);
 }
 assert.equal((await record()).current_hp,37,'Subsequent damage restores expected HP');

 const resourcesPanel=page.locator('#sheet-play-view [data-battle-action="resources"]');
 assert.equal(await resourcesPanel.count(),1);
 // The category remembers its disclosure state across tab changes. Close it
 // explicitly before testing expansion instead of assuming its initial state.
 if(await resourcesPanel.getAttribute('open')!==null)
  await resourcesPanel.locator('summary.play-battle-summary').click();
 assert.equal(await resourcesPanel.getAttribute('open'),null,'Risorse can be collapsed');
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
 assert.match(await focusResource.locator('.play-resource-count').textContent(),/4\s*\/\s*7/,
   'The explicit Use action consumed one Focus use across two damage rolls');
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
 assert.equal(await resourcesPanel.locator('[data-resource-privilege="basic-rules"] [data-rule-action="two_weapon"] button:not([disabled])').count(),1,
  'An unavailable secondary attack remains clickable in base rules');
 assert.equal(await resourcesPanel.locator('[data-resource-privilege="basic-rules"] [data-rule-action="spell_cast"] [data-act="action-open-spells"]').count(),1,
  'Base-rule spellcasting opens Powers directly');
 assert.equal(await resourcesPanel.locator('[data-resource-privilege]').count()>0,true,
  'Free abilities belong to their granting traits, not to a generic free tracker');
 assert.equal(await resourcesPanel.locator('[data-resource-privilege] .play-resource-power-row[data-ability-id="free_pulse"]').count(),1);
 assert.equal(await resourcesPanel.locator('[data-ability-resource="free"]').count(),0,
  'No generic free tracker remains');
 assert.equal(await resourcesPanel.locator('.play-resource-free-actions').count(),0);
 const freeActions=page.locator('#sheet-play-view [data-battle-action="others"] [data-action-timing="free"]');
 assert.equal(await freeActions.count(),1,'Free general actions belong beneath Other Actions');
 assert(await freeActions.locator('[data-attack-id]').count()>0);
 const linkedSpell=resourcesPanel.locator('[data-power-spell-id="arcane_light"]');
 assert.equal(await linkedSpell.count(),1,'Tracker-paid spells belong under their resource');
 assert.equal(await linkedSpell.locator('[data-act="battle-cast-resource-spell"]').count(),1,'Dedicated Lancia button is beside the spell details');
 assert.match(await linkedSpell.textContent(),/Azione/);
 assert.doesNotMatch(await linkedSpell.textContent(),/Incantesimo/);
 await linkedSpell.locator('[data-act="power-spell"]').click();
 assert.match(await page.locator('#action-cast-dialog').textContent(),/Light/);
 await page.locator('#action-cast-dialog [data-act="action-cast-cancel"]').first().click();
 assert.equal(await resourcesPanel.locator('[data-resource-privilege] [data-ability-id="arcane_pulse"]').count(),0);
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
 // Restore the one use spent through the optional-die Use button.
 for(const spent of [2]){
   await page.locator('#sheet-context-dialog [data-act="tracker-less"][data-tracker-id="focus"]').click();
   await page.waitForFunction(async expected=>{
     const {listCreatures}=await import('/creatures.js');
     return (await listCreatures())[0].creature.resource_tracker_spent?.focus===expected;
   },spent);
 }
 await page.locator('#sheet-context-dialog [data-act="tracker-more"][data-tracker-id="focus"]').click();
 await dismiss();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus===3;});
 await resourcesPanel.locator('.play-resource-power-row[data-ability-id="arcane_pulse"] [data-act="battle-use-ability"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus===5;});
 // Some ability actions retain their details dialog after updating the tracker.
 // Dismiss it before interacting with the independent spell use control.
 if(await page.locator('#other-ability-dialog').count())
  await page.locator('#other-ability-dialog [data-ability-cancel]').click();
 await resourcesPanel.locator('[data-power-spell-id="arcane_light"] [data-act="battle-cast-resource-spell"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus===6;});
 assert.equal(await page.locator('#action-cast-dialog').count(),0,'Quick Lancia casts without opening spell description');
 await focusButton.click();
 assert.equal(await page.locator('#sheet-context-dialog [data-act="tracker-reset"][data-tracker-id="focus"]').count(),1);
 await page.locator('#sheet-context-dialog [data-act="tracker-reset"][data-tracker-id="focus"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return !(await listCreatures())[0].creature.resource_tracker_spent?.focus;});
 await dismiss();
 // The numeric AC and speed scores must not open their equipment/movement editors.
 const acScore=page.locator('#sheet-play-view .play-vitals [data-act="sheet-score-formula"][data-target="ac"]');
 assert.equal(await acScore.count(),1);
 await acScore.click();
 assert.match(await page.locator('#sheet-score-formula-dialog h2').textContent(),/Classe armatura/);
 assert.equal(await page.locator('#sheet-context-dialog').count(),0);
 await page.locator('#sheet-score-formula-dialog [data-act="close-score-formula"]').click();
 const speedScore=page.locator('#sheet-play-view .play-vitals [data-act="sheet-score-formula"][data-fastest-movement-value]');
 assert.equal(await speedScore.count(),1);
 await speedScore.click();
 assert.match(await page.locator('#sheet-score-formula-dialog h2').textContent(),/Movimento e velocità/);
 await page.locator('#sheet-score-formula-dialog [data-act="close-score-formula"]').click();
 const speedCard=page.locator('#sheet-play-view [data-sheet-context="movement"]');
 // Rendering keeps a movement glyph; atlas pack/slot choices are a detail
 // of the sprite manifest and should not be part of the sheet contract.
 assert.equal(await speedCard.count(),1,'Movement editor remains available');
 assert.equal(await speedCard.locator('.vtt-action-glyph').count(),1,'Movement editor has an icon');
 assert.equal(await movementPanel.locator('summary.play-battle-summary .vtt-action-glyph').count(),1,'Movement section has an icon');
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
 assert.equal(await armorGroup.locator('.battle-ac-manage').count(),0,'No shortcuts into the obsolete character modification editor');
 assert.equal(await shared.locator('[data-field="hand_grip_two_handed"]').count(),1,
   'Versatile grip is offered for an equipped main-hand versatile weapon');
 assert.equal(await shared.locator('[data-field="attack_ability_finesse_only"]').count(),1);
 for(const width of [320,390]){
  await page.setViewportSize({width,height:844});
  const aligned=await weaponsGroup.locator('.equipment-attack-options').evaluate(node=>{
   const labels=[...node.querySelectorAll(':scope > label')].map(label=>label.getBoundingClientRect());
   const ability=node.querySelector('.equipment-attack-ability');
   const select=ability.querySelector('select').getBoundingClientRect();
   const captionRect=ability.getBoundingClientRect();
   const separated=labels.every((rect,i)=>labels.every((other,j)=>i===j||
     rect.bottom<=other.top+1||other.bottom<=rect.top+1));
   return separated&&select.left>=captionRect.left-1&&select.right<=captionRect.right+1;
  });
  assert(aligned,'Attack ability and option labels never overlap at '+width+'px');
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),
    'Equipment popup must not overflow at '+width+'px');
 }
 await page.setViewportSize({width:390,height:844});
 assert.doesNotMatch(await shared.textContent(),/Iniziativa/);
 assert.equal(await page.locator('#sheet-context-dialog footer,#sheet-context-dialog .formula-bonus,#sheet-context-dialog .hint').count(),0);
 assert.equal(await shared.locator('.battle-ac-manage').count(),0,'Retired bonus editor is absent from the shared defense modal');
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
 assert.equal((await page.locator('#sheet-roll-dialog .sheet-roll-math').nth(1).locator('strong').textContent()).trim(),
   'Prova di abilità · Destrezza');
 assert.equal(await page.locator('#sheet-roll-dialog .sheet-roll-provenance').count(),0);
 assert.equal(await page.locator('#sheet-roll-dialog [data-roll-chat-status]:visible').count(),0);
 await page.locator('#sheet-roll-dialog [data-act="close-sheet-roll"]').click();
 // A class saving-throw proficiency must navigate to the exact granted
 // proficiency trait, never a random feature or the generic bonus editor.
 await sheet('info');
 await page.locator('#sheet-play-view [data-target="save:int"]').click();
 const proficiencyLink=page.locator('#sheet-roll-dialog .sheet-roll-origin-term[data-origin-id="class|phb|wizard"]');
 assert.equal(await proficiencyLink.count(),1,'Class save training retains its source');
 await proficiencyLink.click();
 // Proficiency navigation rebuilds Info asynchronously before opening the
 // grant's trait popup; wait for that completion, not just the source click.
 await page.locator('#trait-benefits-dialog').waitFor({state:'visible'});
 assert.equal(await page.locator('#sheet-roll-dialog').count(),0);
 // The older DOM slot for proficiency cards was retired when Info
 // was reorganized. The meaningful contract is the exact opened trait dialog.
 assert.equal(await page.locator('#trait-benefits-dialog').count(),1,
   'Clicking a proficiency term opens its actual trait benefits dialog');
 assert.match(await page.locator('#trait-benefits-dialog h2').textContent(),/Descrizione · Wizard|Competenze/,
  'Class proficiency may be displayed on the owning class overview');
 await page.locator('#trait-benefits-dialog [data-act="trait-benefits-close"]').click();
 // Formula + and applicable + both choose a concrete trait and initialize
 // the correct benefit type and target, without saving a draft.
 await page.locator('#sheet-play-view [data-target="save:int"]').click();
 await page.locator('#sheet-roll-dialog [data-act="sheet-roll-add-bonus"]').click();
 assert.equal(await page.locator('#roll-trait-picker').count(),1);
 await page.locator('#roll-trait-picker [data-act="roll-trait-pick"]').click();
 assert.equal(await page.locator('#trait-benefits-dialog [data-trait-add-form]').isVisible(),true);
 assert.equal(await page.locator('#trait-benefits-dialog [data-trait-add-kind]').inputValue(),'bonus');
 assert.equal(await page.locator('#trait-benefits-dialog [data-trait-fields="bonus"] [name="target"]').inputValue(),'save:int');
 await page.locator('#trait-benefits-dialog [data-act="trait-benefits-close"]').click();
 await page.locator('#sheet-play-view [data-target="save:int"]').click();
 await page.locator('#sheet-roll-dialog [data-act="sheet-roll-add-applicable"]').click();
 await page.locator('#roll-trait-picker [data-act="roll-trait-pick"]').click();
 assert.equal(await page.locator('#trait-benefits-dialog [data-trait-add-kind]').inputValue(),'bonus');
 assert.equal(await page.locator('#trait-benefits-dialog [data-trait-fields="bonus"] [name="target"]').inputValue(),'save:int');
 assert.equal(await page.locator('#trait-benefits-dialog [data-trait-fields="bonus"] [name="tracker_id"]').count(),1);
 await page.locator('#trait-benefits-dialog [data-act="trait-benefits-close"]').click();
 await sheet('battle');
 // Crosshair opens the existing context popup with real tracker controls.
 await page.locator('#sheet-play-view [data-target="attack_hit:item:local_sword"]').first()
   .evaluate(node=>node.click());
 await page.locator('#sheet-roll-dialog [data-act="sheet-roll-open-tracker"]').click();
 await page.locator('#sheet-context-dialog').waitFor({state:'visible'});
 assert.match(await page.locator('#sheet-context-dialog').getAttribute('data-context'),/^(power-resource:tracker:|resource:)focus$/);
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/Focus arcano/);
 await dismiss();
 await popup('rests');
 assert.equal(await page.locator('#sheet-context-dialog [data-rest-die]').count(),0,
  'Hit Dice must not be editable in the initial rest chooser');
 await page.locator('#sheet-context-dialog [data-act="tracker-short"]').click();
 assert.equal(await page.locator('#sheet-context-dialog [data-rest-preview]').count(),1);
 const shortRestDice=page.locator('#sheet-context-dialog [data-rest-preview] [data-rest-die="6"]');
 assert.equal(await shortRestDice.count(),1,'Hit Dice selector belongs to the short-rest confirmation');
 assert.match(await page.locator('#sheet-context-dialog [data-rest-recoveries]').textContent(),/Superiority Die/);
 assert.match(await page.locator('#sheet-context-dialog [data-rest-recoveries]').textContent(),/0 utilizzi recuperati/,
  'Resources with no spent uses still appear in rest forecast');
 assert.equal(await page.locator('#sheet-context-dialog [data-rest-roll-controls]').isVisible(),true,
  'Roll details are visible for the default Hit Die');
 await shortRestDice.fill('2');
 assert.equal(await page.locator('#sheet-context-dialog [data-rest-roll-controls]').isVisible(),true);
 assert.match(await page.locator('#sheet-context-dialog [data-rest-recoveries]').textContent(),/2 da spendere/);
 assert.equal((await record()).hit_dice_spent.d6,undefined,'Preview cannot spend Hit Dice');
 await page.locator('#sheet-context-dialog [data-rest-roll-mode]').selectOption('manual');
 await page.locator('#sheet-context-dialog [data-rest-manual-results]').fill('3, 4');
 await page.locator('#sheet-context-dialog [data-act="tracker-rest-confirm"]').click();
 await page.locator('#sheet-context-dialog .play-rest-confirm h3', {hasText:'Riposo completato'}).waitFor();
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/d6 = 3/);
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/d6 = 4/);
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/Risorse recuperate/);
 await dismiss();
 const afterShort=await record();
 assert.equal(afterShort.resource_tracker_spent.focus,undefined);
 assert.equal(afterShort.hit_dice_spent.d6,2,'Short rest saves spent Hit Dice');
 assert(afterShort.current_hp>=37,'Short rest heals without exceeding maximum');
 await popup('rests');
 assert.equal(await page.locator('#sheet-context-dialog [data-rest-die]').count(),0);
 await page.locator('#sheet-context-dialog [data-act="tracker-long"]').click();
 assert.equal(await page.locator('#sheet-context-dialog [data-rest-preview]').count(),1);
 assert.equal(await page.locator('#sheet-context-dialog [data-rest-die]').count(),0,
  'Long rest restores dice automatically without asking how many to spend');
 const longForecast=await page.locator('#sheet-context-dialog [data-rest-recoveries]').textContent();
 assert.match(longForecast,/Dadi Vita/);
 assert.match(longForecast,/d6/);
 assert.match(longForecast,/Superiority Die/);
 assert.match(longForecast,/Slot incantesimo livello/);
 assert.match(longForecast,/Punti ferita temporanei/);
 await page.locator('#sheet-context-dialog [data-act="tracker-rest-confirm"]').click();
 await page.locator('#sheet-context-dialog .play-rest-confirm h3', {hasText:'Riposo completato'}).waitFor();
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/Dadi Vita d6: 2/);
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/Risorse recuperate/);
 await dismiss();
 const afterLong=await record();
 assert.equal(afterLong.temporary_hp,0,'Long rest expires temporary HP');
 assert.equal(afterLong.hit_dice_spent.d6,undefined,'2014 long rest restores half of five Hit Dice');
 assert.equal(afterLong.pact_slots_spent,0);
 assert.deepEqual(afterLong.spell_slots_spent,Array(10).fill(0));
 assert(afterLong.current_hp>=afterShort.current_hp,'Long rest restores maximum HP');
 await sheet('info');
 assert.equal(await page.locator('#sheet-play-view .play-abilities .play-ability').count(),6);
 assert.equal(await page.locator('#sheet-play-view .play-identity-mark').count(),0);
 await popup('tools');
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/Armi/);
 assert.match(await page.locator('#sheet-context-dialog').textContent(),/Armature/);
 await dismiss();
 await page.locator('#sheet-play-view .play-skills-disclosure > summary').click();
 const skillMarker=key=>page.locator('#sheet-play-view .play-skills [data-target="skill:'+key+'"] .play-skill-rank');
 assert.equal(await skillMarker('arcana').getAttribute('aria-label'),'Competenza');
 assert.equal(await skillMarker('arcana').locator('svg path').count(),1);
 assert.equal(await skillMarker('stealth').getAttribute('aria-label'),'Maestria');
 assert.equal(await skillMarker('stealth').locator('svg path').count(),2);
 assert.equal(await skillMarker('athletics').count(),0,'Untrained skills have no rank indicator');
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
 await sheet('conditions');assert.match(await page.locator('#sheet-play-view').textContent(),/Avvelenato/);assert.match(await page.locator('#sheet-play-view').textContent(),/Livello 2/);
 assert.equal(await page.locator('#sheet-play-view .play-status-card').count(),1);
 assert.deepEqual(await page.locator('#sheet-play-view .play-status-section-head h3').allTextContents(),['Condizioni','Incantesimi','Capacità']);
 assert.equal(await page.locator('#sheet-play-view .play-status-add').count(),3);
 await page.locator('#sheet-play-view [data-state-trait="state|condition:exhaustion:2"]').click();
 await page.locator('.play-info-traits .trait-card[data-trait-key="state|condition:exhaustion:2"][open]').waitFor();
 assert.match(await page.locator('.play-info-traits .trait-card[data-trait-key="state|condition:exhaustion:2"]').textContent(),/Livello 2/);
 assert.equal(await page.locator('#sheet-context-dialog').count(),0);
 await sheet('conditions');
 const poisonedChip=page.locator('#sheet-play-view [data-active-condition="poisoned"]');
 assert.equal(await poisonedChip.locator('[data-act="state-trait-jump"]').count(),1);
 assert.equal(await poisonedChip.locator('[data-act="condition-remove"]').count(),1);
 await poisonedChip.locator('[data-act="condition-remove"]').click();
 assert.equal((await record()).conditions.includes('poisoned'),false);
 await popup('conditions');assert.match(await page.locator('#sheet-context-dialog [data-condition-category="exhaustion_levels"] summary').textContent(),/Indebolimento/);
 await page.locator('#sheet-context-dialog [data-condition="exhaustion:4"]').check();await dismiss();
 assert.equal((await record()).exhaustion,4);
 assert.match(await page.locator('#sheet-play-view').textContent(),/Livello 4/);
 await page.locator('#sheet-play-view [data-active-condition="exhaustion:4"] [data-act="condition-remove"]').click();
 assert.equal((await record()).exhaustion,0);
 assert.equal(await page.locator('[data-active-condition="exhaustion:4"]').count(),0);
 await popup('apply-spell');await page.locator('#condition-spell-picker').selectOption('phb2014_light');await page.locator('#sheet-context-dialog [data-act="condition-add-spell"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.proficiency_origins?.some(r=>r.id==='spell:phb2014_light'&&r.applied===true);});
 await page.waitForFunction(()=>/Incantesimi[\s\S]*Light/.test(document.querySelector('#sheet-play-view')?.textContent||''));
 assert.match(await page.locator('#sheet-play-view').textContent(),/Incantesimi[\s\S]*Light/);
 await page.locator('[data-state-trait="state|spell:phb2014_light"]').click();
 await page.locator('.play-info-traits .trait-card[data-trait-key="state|spell:phb2014_light"][open]').waitFor();
 assert.match(await page.locator('.play-info-traits .trait-card[data-trait-key="state|spell:phb2014_light"]').textContent(),/Light/);
 await sheet('battle');assert.match(await page.locator('.play-status-strip').textContent(),/Light/);
 await sheet('conditions');await page.locator('[data-act="condition-remove-spell"][data-spell-id="phb2014_light"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return !(await listCreatures())[0].creature.proficiency_origins?.some(r=>r.id==='spell:phb2014_light');});
 await sheet('magic');
 assert.equal(await page.locator('.magic-ability-entry').count(),0,'Additional nonspell abilities no longer belong in Poteri');
 const magicFocus=page.locator('#sheet-play-view [data-magic-origin-tracker="focus"]');
 assert.equal(await magicFocus.count(),1,'The original tracker is still listed in Magic');
 const resource=magicFocus.locator('.play-card-head [data-play-magic-tracker="focus"]');
 assert.match(await resource.textContent(),/Focus arcano\s*\d+\s*\/\s*\d+/,
   'The actual mobile origin heading shows the linked tracker name and available uses');
 assert(await resource.isVisible(),'The tracker must be visible rather than kept in the hidden editor bank');
 const inlineGrantedSpell=magicFocus.locator('.play-magic-origin-spell [data-act="sheet-proxy"]');
 assert.equal(await inlineGrantedSpell.count(),1,'Privilege-granted spells appear immediately below their tracker');
 assert.match(await inlineGrantedSpell.textContent(),/Light/);
 assert.match(await inlineGrantedSpell.textContent(),/Trucchetto/);
 assert.match(await inlineGrantedSpell.textContent(),/−1/);
 assert.equal(await page.locator('#sheet-context-dialog').count(),0,'Granted spell is visible without opening the tracker');
 await inlineGrantedSpell.click();
 assert.match(await page.locator('#action-cast-dialog').textContent(),/Light/);
 await page.locator('#action-cast-dialog [data-act="action-cast-cancel"]').first().click();
 const trackerActions=magicFocus.locator('[data-play-magic-tracker="focus"]>.play-button');
 assert.equal(await trackerActions.count(),2,'Recover/spend actions stay available beside the tracker in its header');
 const spentBefore=Number((await record()).resource_tracker_spent?.focus||0);
 if(await trackerActions.last().isEnabled()){
  await trackerActions.last().click();
  await page.waitForFunction(async before=>{
   const {listCreatures}=await import('/creatures.js');
   return Number((await listCreatures())[0].creature.resource_tracker_spent?.focus||0)===before+1;
  },spentBefore);
  assert.match(await magicFocus.locator('[data-play-magic-tracker="focus"]').textContent(),/Focus arcano/,
    'The shared tracker remains visible following consumption');
  await trackerActions.first().click();
  await page.waitForFunction(async before=>{
   const {listCreatures}=await import('/creatures.js');
   return Number((await listCreatures())[0].creature.resource_tracker_spent?.focus||0)===before;
  },spentBefore);
 }
 await popup('magic-tools');assert.equal(await page.locator('#sheet-context-dialog .magic-toolbar button:visible').count(),6);await page.locator('#sheet-context-dialog [data-magic-tool="slots"]').click();await page.locator('#magic-tools-dialog').waitFor();assert.equal(await page.locator('#sheet-context-dialog').count(),0);await page.locator('[data-act="magic-tool-close"]').click();
 await sheet('info');assert.equal(await page.locator('#sheet-play-view [data-sheet-context="trait-notes"]').count(),0);
 const traitSection=page.locator('.play-info-traits');
 assert.equal(await traitSection.count(),1);
 assert.equal(await traitSection.locator(':scope > h2.play-section-divider').textContent(),'Tratti',
  'Tratti uses the same fixed divider heading as Competenze');
 assert.equal(await traitSection.locator('.play-traits-disclosure').count(),0,
  'Tratti must not be collapsible');
 assert(await traitSection.locator('.trait-origin-group:visible').count()>0,
  'Trait groups are always visible, without opening a disclosure');
 // Adjacent entries, origins and sections must each have one CSS rule, not
 // overlapping bottom- and top-borders.
 const borders=await traitSection.evaluate(section=>{
  const width=(node,side)=>node?parseFloat(getComputedStyle(node)[side])||0:0;
  const lastRow=origin=>origin?.querySelector(':scope > .trait-origin-cards:last-child > .trait-row:last-child');
  let checked=0,duplicates=0,missing=0;
  const check=(last,next)=>{
   if(!last||!next)return;
   checked++;
   const total=width(last,'borderBottomWidth')+width(next,'borderTopWidth');
   if(total>1.5)duplicates++;
   if(total<0.5)missing++;
  };
  const categories=[...section.querySelectorAll('.trait-category')];
  for(const category of categories){
   const origins=[...category.querySelectorAll(':scope > .trait-origin-group')];
   for(let i=1;i<origins.length;i++)check(lastRow(origins[i-1]),origins[i]);
  }
  for(let i=1;i<categories.length;i++){
   const origins=[...categories[i-1].querySelectorAll(':scope > .trait-origin-group')];
   check(lastRow(origins[origins.length-1]),categories[i]);
  }
  return {checked,duplicates,missing};
 });
 assert(borders.checked>0,'At least one adjacent trait section was checked');
 assert.equal(borders.duplicates,0,'Trait sections must not draw double divider lines');
 assert.equal(borders.missing,0,'Trait sections must retain one divider line');
 // Benefits and description must be independent controls.
 assert.equal(await page.locator('.play-info-traits .trait-category-title').count(),0,
  'Origin category labels are inline before each stronger origin name, not separate headings');
 assert(await page.locator('.play-info-traits .trait-origin-title .trait-origin-kind').count()>0);
 assert(await page.locator('.play-info-traits .trait-origin-title .trait-origin-name').count()>0);
 for(const type of ['talenti','oggetti']){
  const section=page.locator('.play-info-traits [data-trait-category="'+type+'"]');
  if(await section.count()){
   assert.equal(await section.locator(':scope > .trait-category-heading').count(),1,
    'One prominent title per '+type+' category');
   assert.equal((await section.locator(':scope > .trait-category-heading').innerText()).trim(),
    type==='talenti'?'Talenti':'Oggetti');
   assert.equal(await section.locator('.trait-origin-group > .trait-origin-title').count(),0,
    'No duplicate headings for individual feats or items');
  }
 }
 const firstTrait=page.locator('.play-info-traits .trait-row').first();
 const traitDescription=firstTrait.locator('details.trait-card');
 assert.equal(await firstTrait.getAttribute('data-trait-enabled'),'true',
  'Every non-explicitly-disabled privilege is enabled by default');
 assert.doesNotMatch(await traitDescription.locator('summary').innerText(),/disattivato/i);
 assert.equal(await traitDescription.locator('.trait-chevron svg path').count(),1,
  'A shallow rounded SVG chevron indicates expansion');
 assert.equal(await traitDescription.getAttribute('open'),null);
 const trigger=firstTrait.locator('[data-act="trait-benefits-open"]');
 assert.equal(await trigger.count(),1);
 await trigger.click();
 const benefitDialog=page.locator('#trait-benefits-dialog[open]');
 await benefitDialog.waitFor();
 assert.equal(await traitDescription.getAttribute('open'),null,'Benefit icon must not expand trait lore');
 // Closing cannot await a pending form save or carry an unsaved draft into the
 // next popup. Exercise X and native Escape in an actual browser.
 await benefitDialog.locator('[data-act="trait-benefits-add"]').click();
 await benefitDialog.locator('[data-trait-fields="bonus"] [name="expression"]').fill('99');
 await benefitDialog.locator('[data-act="trait-benefits-close"]').click();
 await benefitDialog.waitFor({state:'detached'});
 await trigger.click();await benefitDialog.waitFor();
 assert.equal(await benefitDialog.locator('[data-trait-add-form]').isVisible(),false,
  'A dismissed unsaved benefit draft must stay closed on reopening');
 assert.equal((await record()).formula_bonuses?.filter(x=>x.id?.startsWith('trait:')).length||0,0);
 await page.keyboard.press('Escape');
 await benefitDialog.waitFor({state:'detached'});
 await trigger.click();await benefitDialog.waitFor();
 const activeSwitch=benefitDialog.locator('[data-act="trait-benefits-toggle"]');
 assert.equal(await activeSwitch.getAttribute('aria-checked'),'true');
 await activeSwitch.click();
 await page.waitForFunction(()=>document.querySelector('.play-info-traits .trait-row')?.dataset.traitEnabled==='false');
 assert.equal(await benefitDialog.locator('[data-act="trait-benefits-toggle"]').getAttribute('aria-checked'),'false');
 assert.doesNotMatch(await firstTrait.locator('summary').innerText(),/disattivato/i,
  'Inactive state must be conveyed by the row surface, never appended to the name');
 await benefitDialog.locator('[data-act="trait-benefits-toggle"]').click();
 await page.waitForFunction(()=>document.querySelector('.play-info-traits .trait-row')?.dataset.traitEnabled==='true');
 assert.equal(await benefitDialog.locator('[data-act="trait-benefits-toggle"]').getAttribute('aria-checked'),'true');
 assert.equal(await benefitDialog.locator('[data-trait-add-form]').isVisible(),false);
 await benefitDialog.locator('[data-act="trait-benefits-add"]').click();
 assert.equal(await benefitDialog.locator('[data-trait-add-form]').isVisible(),true);
 await benefitDialog.locator('[data-trait-fields="bonus"] [name="target"]').selectOption('initiative');
 await benefitDialog.locator('[data-trait-fields="bonus"] [name="expression"]').fill('2');
 assert.equal((await record()).formula_bonuses?.filter(x=>x.id?.startsWith('trait:')).length||0,0,
  'Typing a benefit must not autosave');
 await benefitDialog.locator('[data-act="trait-benefits-save"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0].creature.formula_bonuses?.some(x=>x.id?.startsWith('trait:')&&x.expression==='2');
 });
 await benefitDialog.locator('[data-trait-add-form]').waitFor({state:'hidden'});
 assert.equal(await benefitDialog.locator('[data-trait-add-form]').isVisible(),false,
  'Saved form must close once persistence and refresh complete');
 await benefitDialog.locator('[data-act="trait-benefits-close"]').click();
 await trigger.click();
 assert.equal(await benefitDialog.locator('[data-trait-add-form]').isVisible(),false,
  'Reopening the popup must never reopen its add form');
 assert.equal(await benefitDialog.locator('.trait-benefit-confirm').count(),0,
  'Opening a benefit panel must never inherit a pending deletion');
 const removeButton=benefitDialog.locator('[data-act="trait-benefits-remove-request"][data-benefit-id^="bonus:trait:"]');
 await benefitDialog.evaluate(dialog=>{dialog.dataset.regressionMarker='same-modal';});
 // A synthetic click without a pointerdown on this X represents a mobile
 // click-through: only a fresh intentional press can start deletion.
 await removeButton.evaluate(button=>button.dispatchEvent(new MouseEvent('click',
  {bubbles:true,cancelable:true,detail:1})));
 assert.equal(await benefitDialog.locator('.trait-benefit-confirm').count(),0,
  'A click without a new pointer gesture must not ask to delete a benefit');
 await removeButton.click();
 assert.equal(await benefitDialog.getAttribute('data-regression-marker'),'same-modal',
  'Removal request must not rebuild the modal or character sheet');
 assert.equal(await benefitDialog.locator('.trait-benefit-confirm').count(),1);
 assert.equal((await record()).formula_bonuses.filter(x=>x.id?.startsWith('trait:')).length,1,
  'First removal click only asks for confirmation');
 await benefitDialog.locator('[data-act="trait-benefits-remove-cancel"]').click();
 assert.equal(await benefitDialog.locator('.trait-benefit-confirm').count(),0,
  'Cancel clears the pending deletion without redrawing');
 await removeButton.click();
 assert.equal(await benefitDialog.locator('.trait-benefit-confirm').count(),1);
 await activeSwitch.click();
 await page.waitForFunction(()=>document.querySelector('.play-info-traits .trait-row')?.dataset.traitEnabled==='false');
 assert.equal(await benefitDialog.locator('.trait-benefit-confirm').count(),0,
  'A refresh after changing a trait must not resurrect a pending deletion');
 await activeSwitch.click();
 await page.waitForFunction(()=>document.querySelector('.play-info-traits .trait-row')?.dataset.traitEnabled==='true');
 await removeButton.click();
 await benefitDialog.locator('[data-act="trait-benefits-remove-confirm"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');
  return !(await listCreatures())[0].creature.formula_bonuses?.some(x=>x.id?.startsWith('trait:'));
 });
 await benefitDialog.locator('[data-act="trait-benefits-close"]').click();
 assert.equal(await benefitDialog.count(),0);
 await traitDescription.locator(':scope > summary').click();
 assert.equal(await traitDescription.getAttribute('open'),'');
 assert.equal(await traitDescription.locator('.trait-benefits').count(),0,
  'Expanded trait contains only description, never benefits');
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
 assert.equal(await page.locator('#sheet-play-view [data-battle-action="movement"]').count(),0,
  'Movement choices are integrated in Azioni');
 assert(await page.locator('#sheet-play-view [data-battle-action="others"]').evaluate(node=>
  Boolean(node.compareDocumentPosition(document.querySelector('#sheet-play-view [data-battle-action="checks"]'))&Node.DOCUMENT_POSITION_FOLLOWING)),
  'Azioni is rendered before Prove abilità');
 const checks=page.locator('#sheet-play-view [data-battle-action="checks"]');
 await checks.locator('summary.play-battle-summary').click();
 assert.equal(await checks.locator('[data-action-ability]').count(),6);
 assert.equal(await checks.locator('.play-battle-attack-entry').count(),24);
 const strength=checks.locator('[data-action-ability="str"]');
 assert.equal(await strength.locator('.play-battle-attack-entry').first().getAttribute('data-attack-id'),'ability_check:str');
 assert.equal(await strength.locator('[data-target="skill:athletics"]').count(),1);
 assert.equal(await checks.locator('[data-action-ability="con"] .play-battle-attack-entry').count(),1);
 if((await strength.getAttribute('open'))!==null)
  await strength.locator('summary.play-battle-action-heading').click();
 assert.equal(await strength.getAttribute('open'),null,'Ability groups can be closed before opening');
 await strength.locator('summary.play-battle-action-heading').click();
 const firstRoll=strength.locator('[data-target="ability_check:str"]');
 await firstRoll.click();
 assert.equal((await page.locator('#sheet-roll-dialog .sheet-roll-math').nth(1).locator('strong').textContent()).trim(),
   'Prova di caratteristica');
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
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('conditions');
 await page.locator('[data-state-trait="state|rage"]').click();
 await page.locator('.play-info-traits .trait-card[data-trait-key="state|rage"][open]').waitFor();
 await sheet('battle');
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
 console.log('PASS: 5 play sheets at 320/360/390/430px and landscape, contextual editing, HP, tracker recovery, skills, inventory descriptions/quantity, documents, conditions, spell tools, every context link and offline persistence.');
}finally{await f.close();}
