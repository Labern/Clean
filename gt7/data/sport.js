// Sport Mode: how ratings work and how to climb.

export const RATINGS = {
  dr: { name: 'Driver Rating (DR)', ladder: ['E', 'D', 'C', 'B', 'A', 'A+'], what: 'Your pace. It rises when you beat drivers rated above you and falls when slower-rated drivers beat you. It is relative: a 6th from the back of an A lobby can earn more than a win in a D lobby.' },
  sr: { name: 'Sportsmanship Rating (SR)', ladder: ['E', 'D', 'C', 'B', 'A', 'S'], what: 'How clean you are. Clean sectors raise it. Collisions, track-limit penalties and wall contact lower it. Matchmaking leans on SR, so protect it first and the lobbies get cleaner.' },
};

export const SPORT_GUIDE = [
  { t: 'The Daily Races', d: 'Three races (A, B, C) rotate every week, usually with fixed cars or BoP Gr.4/Gr.3. Practise the week\'s tracks offline before racing.' },
  { t: 'Qualifying', d: 'Set a clean time. Your grid slot depends on it. Run it on fresh tyres after a warm-up lap.' },
  { t: 'Lap 1', d: 'Most SR loss happens in the first three corners. Brake early into T1, leave space, and take positions on lap 2.' },
  { t: 'Penalties', d: 'Shortcut penalties for cutting track limits, collision penalties for contact. Serve them by lifting on a straight. Fighting them costs more time.' },
  { t: 'Racecraft', d: 'One defensive move. Give a car\'s width at the apex when someone is alongside. Don\'t dive in from more than a car length back.' },
  { t: 'Consistency beats hero laps', d: 'A finish five places up without contact moves DR and SR more than a crash while chasing a podium.' },
  { t: 'GT World Series', d: 'Nations Cup (for your country) and Manufacturers Cup (for a brand). Qualifying rounds run through Sport Mode. Pick a manufacturer you love: Nissan has deep GT roots.' },
];

export const BOP = 'Balance of Performance (BoP) sets power and weight so every car in a class (Gr.4, Gr.3, Gr.1) is within a few tenths. In BoP races you can\'t tune, except brake balance and the fuel map. So pick the car whose handling suits your style, not the "fastest" one.';
