const CACHE='mausch-v4';

self.addEventListener('install',e=>e.waitUntil(
  caches.open(CACHE).then(c=>c.addAll([
    './',
    './index.html',
    './manifest.webmanifest',
    './icon-192.png',
    './icon-512.png'
  ])).then(()=>self.skipWaiting())
));

self.addEventListener('activate',e=>e.waitUntil(
  caches.keys().then(keys=>Promise.all(
    keys.filter(k=>k.startsWith('mausch-')&&k!==CACHE)
      .map(k=>caches.delete(k))
  )).then(()=>self.clients.claim())
));

self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET')return;
  const isAppShell=e.request.mode==='navigate'||new URL(e.request.url).pathname.endsWith('/index.html');
  if(isAppShell){
    e.respondWith(fetch(e.request).then(response=>{
      if(response.ok)caches.open(CACHE).then(c=>c.put('./index.html',response.clone()));
      return response;
    }).catch(()=>caches.match(e.request).then(cached=>cached||caches.match('./index.html'))));
    return;
  }
  e.respondWith(caches.match(e.request).then(response=>response||fetch(e.request)));
});
