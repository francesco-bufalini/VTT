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
 assert.doesNotMatch(ui,/data-session-pane="connection"|sessionLayout\(/);
 assert.doesNotMatch(ui,/data-session-content="chat"/);
 assert.match(ui,/chatScreen\.addEventListener\("submit",onFormSubmit\)/);
 assert.match(ui,/function setSheetChatOpen\(open\)/);
 assert.match(ui,/if\(!onCreature\)state\.chatOpen=false/);
 assert.match(ui,/chatScreen\.querySelector\('#events'\)\?\.focus/);
 assert.doesNotMatch(ui,/chat-view-close|chat-main-panel|chat-view-head/);
 assert.match(ui,/const author=activeChatCreatureName\(\)/);
 assert.doesNotMatch(ui,/id="chat-author"/);
 assert.match(ui,/const topbar=document\.querySelector\('\.topbar'\)/);
 assert.match(ui,/topbar\.hidden=state\.page==='session'\|\|state\.page==='library'&&state\.libraryMode/);
 assert.match(ui,/topSessionButton\.hidden=hasCreature/);
 assert.match(ui,/sessionTab\.classList\.toggle\('session-connected',sessionConnected\)/);
 assert.match(ui,/button\.classList\.toggle\('session-connected',sessionConnected\)/);
 assert.match(html,/id="creature-forms" class="header-icon-button header-forms"/);
 assert.match(ui,/id="chat-message" type="text"/);
 assert.match(ui,/class="chat-send-button"/);
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

test('chat is frameless and uses the current creature as sender',()=>{
 const theme=readFileSync(new URL('../mobile_metal_theme.css',import.meta.url),'utf8');
 assert.match(theme,/\.app-shell\.chat-open \.chat-screen\{[\s\S]*?padding:0;overflow:hidden/);
 assert.match(theme,/\.chat-screen #chat-form\.chat-composer\{[\s\S]*?display:flex/);
 assert.match(theme,/\.chat-screen #chat-message\{[\s\S]*?height:42px/);
 assert.match(theme,/\.play-dock #dock-session\.session-connected::after/);
 assert.match(theme,/\.topbar\[hidden\],\.topbar \.connection-link\[hidden\]/);
 assert.doesNotMatch(ui,/Scrivi come|Chat della partita<\/h2>|data-act="header-chat-close"/);
 assert.match(ui,/author:String\(r\.author\|\|activeChatCreatureName\(\)\)/);
});

test('dice avoids input autofocus, variants use paw icon and preferences are minimal',()=>{
 const theme=readFileSync(new URL('../mobile_metal_theme.css',import.meta.url),'utf8');
 assert.match(ui,/<h2 id="chat-dice-title" tabindex="-1" autofocus>/);
 assert.match(ui,/forms\.innerHTML=actionGlyph\('wild_shape'\)/);
 assert.doesNotMatch(html,/id="creature-forms"[^>]*><svg/);
 assert.match(theme,/\.topbar #creature-forms \.vtt-action-glyph\{/);
 assert.match(theme,/\.distance-preferences-body fieldset\{\s*display:grid;grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/);
 assert.match(theme,/\.distance-preferences-body \.distance-preferences-option input\[type="radio"\]\{/);
 assert.doesNotMatch(ui,/Unità originale delle regole D&D|La preferenza cambia solo le distanze visualizzate/);
 assert.match(ui,/\[\['feet','Piedi \(ft\)'\],\['meters','Metri \(m\)'\]\]/);
});

test('Partita uses one compact server bar before the map with no switcher or header',()=>{
 const theme=readFileSync(new URL('../mobile_metal_theme.css',import.meta.url),'utf8');
 const gd=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 assert.match(ui,/const desktop='<section class="panel session-desktop" aria-label="Collegamento al server">/);
 assert.match(ui,/return desktop\+html/);
 assert.match(ui,/html\+=sessionCreatureWarnings\(\)/);
 assert.doesNotMatch(ui,/header\('Al tavolo'|class="session-switcher"|data-session-content="connection"/);
 assert.match(ui,/state\.serverDeviceName=String\(result\.device_name\|\|''\)/);
 assert.match(ui,/esc\(serverName\)/);
 assert.match(ui,/session-server-name[\s\S]*?session-connection-state/);
 assert.match(ui,/class="session-connection-actions"/);
 assert.match(ui,/btn\('disconnect','Dissocia','danger'\)/);
 assert.match(theme,/\.session-connection-actions\{display:flex/);
 assert.match(gd,/"device_name": _server_device_name\(\)/);
 assert.match(gd,/OS\.get_environment\("COMPUTERNAME"\)/);
});
