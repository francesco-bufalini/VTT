// The embedded sheet uses the native archive; it never creates a browser copy.
import {request} from './bridge.js';
export const DATABASE_NAME = 'vtt-desktop-native';
export const DATABASE_VERSION = 1;
export const openStorage = async () => { await request('owner'); return {close(){}}; };
export const localOwnerId = () => request('owner');
export const getRecord = (scope,type,id) => request('get',{scope,type,id});
export const listRecords = (scope,type=null) => request('list',{scope,type});
export const putRecord = (scope,type,id,data,expectedRevision=null) => request('put',{scope,type,id,data,expectedRevision});
export const deleteRecordIfRevision = (scope,type,id,expectedRevision) => request('delete',{scope,type,id,expectedRevision});
export const deleteCreatureFamily = (scope, entries) => request('deleteFamily',{scope,type:'creature',entries});
export const deleteRecord = async () => { throw Error('La cancellazione richiede una revisione della scheda.'); };
export const insertRecords = () => nativeOperation();
export const exportBackup = () => nativeOperation();
export const importBackup = () => nativeOperation();
export const putAttachment = () => nativeOperation();
export const getAttachment = () => nativeOperation();
async function nativeOperation(){throw Error('Per importazioni, backup e allegati usa «Strumenti nativi» in alto.');}
export const setting = (key,...values) => request('setting',{key,...(values.length?{value:values[0]}:{})});
export async function getOrCreateSetting(key,makeValue){
  const old=await setting(key); return old??setting(key,makeValue());
}
// Tactical connectivity belongs to the native board in this first migration.
export const queueAction = async () => {throw Error('Usa la mappa nativa per questa azione.');};
export const pendingActions = async () => [];
export const acknowledgeAction = async () => {};
export const storageEstimate = async () => ({});
export const requestPersistentStorage = async () => true;
