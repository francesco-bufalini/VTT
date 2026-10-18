import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {actionGlyph} from "../action_economy.js";
import {snapshotBlob} from "../session_map.js";

const read=(path)=>readFileSync(new URL(path,import.meta.url),"utf8");

test("action icons use packaged sprite slot classes, no CSP-blocked inline styles",()=>{
  const css=read("../styles.css");
  for(const key of ["action","bonus","inventory","condition","spell_cast","weapon","wild_shape"]){
    const markup=actionGlyph(key);
    assert.match(markup,/vtt-action-glyph--pack-[0-3]/);
    assert.match(markup,/vtt-action-glyph--slot-\d+/);
    assert.ok(!markup.includes("style="));
  }
  assert.ok(css.includes(".vtt-action-glyph--slot-24"));
  assert.ok(css.includes(".vtt-action-glyph--pack-3.vtt-action-glyph--slot-22"));
});

test("inline session preview is backed by CSP-authorized, revocable object URLs",()=>{
  const ui=read("../ui.js");
  const host=read("../../network/pwa_host.gd");
  assert.ok(ui.includes("URL.createObjectURL(blob)"));
  assert.ok(ui.includes("URL.revokeObjectURL(url)"));
  assert.ok(ui.includes("URL.revokeObjectURL(oldUrl)"));
  assert.ok(ui.includes("snapshotObjectUrl"));
  assert.ok(!ui.includes("data:image/webp;base64,"));
  assert.ok(host.includes("img-src 'self' blob:"));
  const blob=snapshotBlob({ok:true,format:"webp",image:"d2VicA=="});
  assert.equal(blob.type,"image/webp");
});

test("PWA shell version changes so installed browsers receive the CSP repair",()=>{
  assert.match(read("../sw.js"), /vtt-mobile-shell-v(?:4[5-9]|[5-9][0-9]|[0-9]{3,})/);
  assert.ok(read("../index.html").includes('name="mobile-web-app-capable"'));
});
