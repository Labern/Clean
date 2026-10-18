// All track guides. Real circuits carry `map` (an id in maps.js, real OSM
// geometry); GT originals have map: null and render as a lap strip.
import icons from './tracks/icons.js';
import classics from './tracks/classics.js';
import more from './tracks/more.js';
import originals from './tracks/originals.js';

export const TRACKS = [...icons, ...classics, ...more, ...originals];
export const trackById = Object.fromEntries(TRACKS.map((t) => [t.id, t]));
