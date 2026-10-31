import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {isIncomingExternalEvent} from '../chat_notifications.js';

const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const ui=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
const styles=readFileSync(new URL('../styles.css',import.meta.url),'utf8');

test('chat and dice header actions belong only to an opened creature',()=>{
 assert.match(html,/id="header-chat"[^>]*data-act="header-chat-open"/);
 assert.match(html,/id="header-chat-notifications"[^>]*data-act="toggle-chat-notifications"/);
 assert.match(html,/id="header-dice"[^>]*data-act="open-chat-dice"/);
 assert.match(ui,/function isCreatureOpen\(\)\{\s*return state\.page==='library'&&!state\.libraryMode&&Boolean\(state\.creatureId\)/);
 assert.match(ui,/headerChat\.hidden=!onCreature\|\|state\.chatOpen/);
 assert.match(ui,/headerBell\.hidden=!onCreature\|\|!state\.chatOpen/);
 assert.match(ui,/headerDice\.hidden=!onCreature/);
 assert.match(styles,/\.header-chat-button\.has-unread::after/);
});

test('chat replaces the sheet and dock without replacing the topbar',()=>{
 const appEnd=html.indexOf('</main>');
 const screen=html.indexOf('id="chat-screen"');
 assert(appEnd>=0&&screen>appEnd,'Chat is outside the sheet <main>');
 assert.match(styles,/\.app-shell\.chat-open #app,\.app-shell\.chat-open #mobile-tabs\{display:none!important\}/);
 assert.match(styles,/\.app-shell\.chat-open \.chat-screen\{display:flex/);
 assert.match(ui,/const choices=\[\['table','Mappa'\],\['connection','Collegamento'\]\]/);
 assert.doesNotMatch(ui,/data-session-content="chat"/);
 assert.match(ui,/chatScreen\.addEventListener\("submit",onFormSubmit\)/);
 assert.match(ui,/function setSheetChatOpen\(open\)/);
 assert.match(ui,/if\(!onCreature\)state\.chatOpen=false/);
 assert.match(ui,/chatScreen\.querySelector\('\.chat-view-close'\)\?\.focus/);
});

test('incoming marker excludes own activity, local echoes, old history and map updates',()=>{
 const localIds=new Set(['mine']);
 const sentIds=new Set(['sent']);
 const opts={localIds,locallySentIds:sentIds};
 assert.equal(isIncomingExternalEvent({id:'other-chat',kind:'chat'},opts),true);
 assert.equal(isIncomingExternalEvent({id:'other-roll',kind:'roll'},opts),true);
 assert.equal(isIncomingExternalEvent({id:'other-action',kind:'action'},opts),true);
 assert.equal(isIncomingExternalEvent({id:'mine',kind:'action'},opts),false);
 assert.equal(isIncomingExternalEvent({id:'mine',kind:'chat'},opts),false);
 assert.equal(isIncomingExternalEvent({id:'sent',kind:'roll'},opts),false);
 assert.equal(isIncomingExternalEvent({id:'map',kind:'map_update'},opts),false);
 assert.equal(isIncomingExternalEvent({id:'old',kind:'chat'},{...opts,initialHistory:true}),false);
 assert.equal(isIncomingExternalEvent({kind:'chat'},opts),false);
 assert.match(ui,/if\(incomingEvents\.length&&!state\.chatOpen\)\{\s*state\.chatUnread=true;syncNav\(\)/);
 assert.match(ui,/if\(open\)state\.chatUnread=false/);
});

test('dice stays a dialog and logs completed rolls to local chat',()=>{
 assert.match(ui,/function openDiceDialog\(\)/);
 assert.match(ui,/if\(act==="open-chat-dice"\)\{openDiceDialog\(\);return;\}/);
 assert.match(ui,/if\(act==="roll"\)\{await roll\(state\.diceSides\);return;\}/);
 assert.match(ui,/async function shareRoll\(\{quiet=false,roll=null\}=\{\}\)/);
 assert.match(ui,/rememberChatEvent\(event\)/);
 assert.match(ui,/chatScreen\.querySelector\('#events'\)/);
});
