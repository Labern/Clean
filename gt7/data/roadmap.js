// The endgame ladder, from "Café finished" to alien pace. Every step is a
// checklist item; the Command Centre picks the next one by `prio`, adjusted
// by the goals you chose in onboarding (focus tags).

export const PHASES = [
  {
    id: 'foundations', title: 'Foundations', kicker: 'Phase 1',
    blurb: 'You finished the Café on talent. Now make that talent systematic. The licences and Circuit Experiences teach exactly the skills Sport Mode needs, and they pay.',
    steps: [
      { id: 'lic-ib', title: 'International B licence: all gold', prio: 10, focus: ['pace', 'sport'], how: 'Retry each test until gold. They drill braking points and car control.' },
      { id: 'lic-ia', title: 'International A licence: all gold', prio: 11, focus: ['pace', 'sport'], how: 'Harder car-control tests. Use the wheel: these are perfect wheel calibration.' },
      { id: 'lic-s', title: 'Super licence: all gold', prio: 12, focus: ['pace', 'sport'], how: 'The real test of racecraft. Gold here means you are ready for Sport Mode.' },
      { id: 'ce-ring', title: 'Circuit Experience: Nordschleife (gold)', prio: 14, focus: ['pace', 'collect'], how: 'The big payout CE, and the best way to learn the Ring in sections.' },
      { id: 'ce-spa', title: 'Circuit Experience: Spa (gold)', prio: 15, focus: ['pace'], how: 'Each sector, then the full lap.' },
      { id: 'ce-all', title: 'Every Circuit Experience at gold', prio: 30, focus: ['pace', 'collect'], how: 'Credits plus track knowledge for every circuit in the game.' },
      { id: 'missions', title: 'All Missions complete', prio: 25, focus: ['collect'], how: 'Rewards include cars you can\'t buy easily.' },
      { id: 'wheel-setup', title: 'Wheel & pedals dialled in (Wheel Lab)', prio: 5, focus: ['wheel'], how: 'Set FFB, rotation and pedal calibration once, properly. Everything after builds on it.' },
    ],
  },
  {
    id: 'engine', title: 'Credit Engine', kicker: 'Phase 2',
    blurb: 'Big cars cost big credits. Build a repeatable loop, and buy the tool that multiplies it first.',
    steps: [
      { id: 'buy-grinder', title: 'Buy a Gr.1 grind car (919 Hybrid or TS050)', prio: 16, focus: ['collect'], how: 'About 3M Cr. Detuned to 800 PP, it wins the WTC 800, which pays 727,500 Cr per clean race.', car: 'porsche919' },
      { id: 'grind-loop', title: 'Run the WTC 800 loop until your first big target', prio: 18, focus: ['collect'], how: 'Track runs in the Credit Engine to see your real credits per hour.' },
      { id: 'daily-habit', title: 'Make the Daily Workout a habit', prio: 19, focus: ['collect'], how: '42 km per day. Grinding covers it automatically.' },
    ],
  },
  {
    id: 'garage', title: 'The Garage', kicker: 'Phase 3',
    blurb: 'Buy in the right order: race cars that win you credits and races first, then hypercars, then the Legend collection.',
    steps: [
      { id: 'buy-gr3', title: 'Buy your Gr.3 weapon', prio: 20, focus: ['sport', 'pace'], how: 'The RSR (991) is the recommendation: stable, fast, forgiving. 450,000 Cr.', car: 'rsr991' },
      { id: 'buy-gr4', title: 'Buy a Gr.4 car', prio: 22, focus: ['sport'], how: 'Cayman GT4 Clubsport. Daily Race A often uses Gr.4.', car: 'caymangt4' },
      { id: 'buy-r34', title: 'Buy the R34 Nür (heritage)', prio: 26, focus: ['heritage', 'collect'], how: 'The car GT was built on. Check the Legend Cars rotation.', car: 'r34' },
      { id: 'buy-787b', title: 'Buy the Mazda 787B', prio: 28, focus: ['heritage', 'collect'], how: 'The only rotary Le Mans winner.', car: 'mazda787b' },
      { id: 'buy-f1', title: 'Buy the McLaren F1', prio: 40, focus: ['collect'], how: '≈18M Cr in Legend Cars. Watch the rotation.', car: 'mclarenf1' },
      { id: 'buy-250gto', title: 'Buy the Ferrari 250 GTO', prio: 45, focus: ['collect'], how: '≈20M Cr. The endgame flex.', car: 'f250gto' },
      { id: 'twenty-club', title: 'Own the full 20M club', prio: 60, focus: ['collect'], how: '250 GTO, XJ13, W196, 330 P4, 917K, D-Type, McLaren F1.' },
    ],
  },
  {
    id: 'tuning', title: 'Tuning Mastery', kicker: 'Phase 4',
    blurb: 'Learn to read a car and fix it. That is how you win events outside BoP.',
    steps: [
      { id: 'tune-basics', title: 'Complete the Tuning Lab fundamentals', prio: 32, focus: ['tune'], how: 'Springs, dampers, anti-roll bars, LSD, aero, brake balance.' },
      { id: 'tune-pp', title: 'Build a car to an exact PP limit', prio: 34, focus: ['tune', 'collect'], how: 'Restrictor + ballast to hit 800 PP precisely without losing balance.' },
      { id: 'tune-own', title: 'Make your own setup for one track', prio: 36, focus: ['tune', 'pace'], how: 'Pick your favourite track and car. Change one thing at a time.' },
    ],
  },
  {
    id: 'sport', title: 'Sport Mode', kicker: 'Phase 5',
    blurb: 'Racing real people. Driver Rating (DR) measures your pace; Sportsmanship Rating (SR) measures how clean you are. Protect SR first.',
    steps: [
      { id: 'sport-first', title: 'First Daily Race: finish clean', prio: 24, focus: ['sport'], how: 'Qualify, start at the back if unsure, finish without contact. SR first.' },
      { id: 'sport-sr-s', title: 'Reach SR S', prio: 38, focus: ['sport'], how: 'Clean races. SR S gets you matched with clean drivers.' },
      { id: 'sport-dr-b', title: 'Reach DR B', prio: 42, focus: ['sport', 'pace'], how: 'Consistent top-half finishes.' },
      { id: 'sport-dr-a', title: 'Reach DR A', prio: 50, focus: ['sport', 'pace'], how: 'Win races against DR A drivers.' },
      { id: 'sport-wcs', title: 'Enter a Nations or Manufacturers Cup round', prio: 55, focus: ['sport'], how: 'GT World Series qualifiers. Pick Nissan for the Manufacturers Cup.' },
    ],
  },
  {
    id: 'alien', title: 'Alien Pace', kicker: 'Phase 6',
    blurb: 'The last few tenths. Racing line theory, rotation at the limit, minimum corner speed, ghosts and telemetry.',
    steps: [
      { id: 'academy', title: 'Finish the Racecraft Academy', prio: 33, focus: ['pace', 'wheel'], how: 'Every lesson, then use each one on a track.' },
      { id: 'apex', title: 'Drive Beyond the Apex', prio: 34, focus: ['pace', 'tune'], how: 'Polyphony\'s own manual, one concept at a time, on the exact corners where you feel it. Run each drill.' },
      { id: 'tt-gold', title: 'Beat "fast" benchmark on 5 tracks', prio: 48, focus: ['pace'], how: 'Log PBs in the track guides.' },
      { id: 'tt-alien', title: 'Hit an "alien" benchmark anywhere', prio: 70, focus: ['pace'], how: 'Download a top ghost and match its braking and minimum speeds.' },
    ],
  },
];

export const FOCUS = {
  sport: 'Online Sport Mode',
  collect: 'Collect every great car',
  pace: 'Raw lap-time pace',
  tune: 'Tuning mastery',
  wheel: 'Get the most from my wheel & pedals',
  heritage: 'Learn 30 years of GT history',
};
