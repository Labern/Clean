// Every drawable circuit: real ones from OpenStreetMap (maps.js) plus the GT
// originals traced from their in-game course maps (maps-gt.js, `traced: true`).
import { MAPS as OSM } from './maps.js';
import { MAPS_GT } from './maps-gt.js';
export const MAPS = { ...OSM, ...MAPS_GT };
