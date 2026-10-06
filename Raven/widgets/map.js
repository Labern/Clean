// The map is the stage, not a tile. Loads Google Maps when a key exists,
// otherwise a styled placeholder so the layout can be judged without one.

import { on, emit, latest } from '../lib/bus.js';

// Night style: Tesla neutrals so the map reads as part of the UI.
const NIGHT = [
  { elementType: 'geometry', stylers: [{ color: '#171a20' }] },
  { elementType: 'labels.text.fill', stylers: [{ color: '#8e8e8e' }] },
  { elementType: 'labels.text.stroke', stylers: [{ color: '#171a20' }] },
  { featureType: 'poi', stylers: [{ visibility: 'off' }] },
  { featureType: 'road', elementType: 'geometry', stylers: [{ color: '#2a2d33' }] },
  { featureType: 'road', elementType: 'geometry.stroke', stylers: [{ color: '#171a20' }] },
  { featureType: 'road.highway', elementType: 'geometry', stylers: [{ color: '#393c41' }] },
  { featureType: 'road.highway', elementType: 'labels.text.fill', stylers: [{ color: '#d0d1d2' }] },
  { featureType: 'water', elementType: 'geometry', stylers: [{ color: '#0b0d11' }] },
  { featureType: 'transit', stylers: [{ visibility: 'off' }] },
  { featureType: 'administrative', elementType: 'geometry.stroke', stylers: [{ color: '#393c41' }] },
];
const DAY = [
  { featureType: 'poi', stylers: [{ visibility: 'off' }] },
  { featureType: 'transit', stylers: [{ visibility: 'off' }] },
];

export function mountMap(host, ctx) {
  const key = globalThis.RAVEN_CONFIG?.googleMapsKey;
  host.innerHTML = '';
  if (!key) { placeholder(host, ctx); return; }

  const el = document.createElement('div');
  el.style.cssText = 'position:absolute;inset:0';
  host.appendChild(el);

  const s = document.createElement('script');
  s.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&libraries=places&v=weekly&loading=async&callback=__ravenMap`;
  s.async = true;
  globalThis.__ravenMap = () => {
    const g = globalThis.google.maps;
    const home = ctx.store.get('home');
    const map = new g.Map(el, {
      center: home, zoom: 13, disableDefaultUI: true, gestureHandling: 'greedy',
      styles: ctx.theme() === 'night' ? NIGHT : DAY, backgroundColor: '#171a20',
    });
    new g.TrafficLayer().setMap(map);
    const car = new g.Marker({ map, position: home, icon: carIcon(g, 0) });
    let follow = true;
    map.addListener('dragstart', () => { follow = false; });
    const place = (t) => {
      if (t.lat == null) return;
      const p = { lat: t.lat, lng: t.lng };
      car.setPosition(p); car.setIcon(carIcon(g, t.heading || 0));
      if (follow) map.panTo(p);
    };
    on('car.pos', place);     // browser GPS, when the car's browser gives it
    on('tesla.state', place); // Fleet API, later
    on('theme', (th) => map.setOptions({ styles: th === 'night' ? NIGHT : DAY }));
    on('map.recenter', () => { follow = true; const t = latest('car.pos') || latest('tesla.state'); if (t?.lat != null) map.panTo({ lat: t.lat, lng: t.lng }); });
    ctx.map = map;
    emit('map.ready', { map });
  };
  s.onerror = () => placeholder(host, ctx, 'Google Maps failed to load');
  document.head.appendChild(s);
}

function carIcon(g, heading) {
  return {
    path: 'M0,-10 L6,8 L0,4 L-6,8 Z',
    fillColor: '#3e6ae1', fillOpacity: 1, strokeColor: '#ffffff', strokeWeight: 1.5,
    scale: 1.6, rotation: heading, anchor: new g.Point(0, 0),
  };
}

function placeholder(host, ctx, msg) {
  const d = document.createElement('div');
  d.id = 'map-placeholder';
  d.innerHTML = `<div class="stack">
    <div class="display t-3xl">${msg || 'Google Maps'}</div>
    <div class="t-lg">${msg ? '' : 'Add <code>googleMapsKey</code> to config.js'}</div>
  </div>`;
  host.appendChild(d);
}
