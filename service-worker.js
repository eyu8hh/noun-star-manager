const CACHE="nsm-shell-v45";
const SHELL=["./","./index.html","./community.html","./assets/noun-star-logo.png","./manifest.webmanifest","./assets/css/app.css","./js/app.js"];
self.addEventListener("install",event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith("nsm-shell-")&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",event=>{const req=event.request;if(req.method!=="GET")return;const url=new URL(req.url);if(url.origin!==self.location.origin)return;event.respondWith((async()=>{const cache=await caches.open(CACHE);if(req.mode==="navigate"){try{const fresh=await fetch(new Request(req,{cache:"no-store"}));if(fresh.ok)cache.put(req,fresh.clone());return fresh}catch{return (await cache.match(req))||(await cache.match("./index.html"))}}const cached=await cache.match(req);if(cached)return cached;try{const fresh=await fetch(req);if(fresh.ok)cache.put(req,fresh.clone());return fresh}catch{return cache.match("./")}})())});

self.addEventListener("push",event=>{
 let payload={};
 try{payload=event.data?event.data.json():{}}catch{payload={body:event.data?.text?.()||""}}
 const title=String(payload.title||"NOUN STAR");
 const options={
  body:String(payload.body||"لديك إشعار جديد من النادي."),
  icon:"./assets/noun-star-logo.png",
  badge:"./assets/noun-star-logo.png",
  tag:String(payload.tag||payload.notificationId||"nsm-push"),
  renotify:false,
  data:{url:String(payload.url||"./"),notificationId:payload.notificationId||null}
 };
 event.waitUntil(self.registration.showNotification(title,options));
});
self.addEventListener("notificationclick",event=>{
 event.notification.close();
 const requested=new URL(event.notification.data?.url||"./",self.registration.scope);
 const target=requested.origin===self.location.origin?requested.href:self.registration.scope;
 event.waitUntil((async()=>{
  const windows=await clients.matchAll({type:"window",includeUncontrolled:true});
  const existing=windows.find(client=>client.url.startsWith(self.registration.scope));
  if(existing){if("navigate" in existing)await existing.navigate(target);await existing.focus();return}
  await clients.openWindow(target);
 })());
});
