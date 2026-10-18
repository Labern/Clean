// Credit Engine data. Payouts are as reported by the sources below and are
// patch-dependent: every row is editable in the app, and your edits win.
//   racinggames.gg "Best credit grinds in Gran Turismo 7" (WTC 800 / WTC 600)
//   coachdaveacademy.com "Top tips to earn credits in GT7" (2026)

export const CLEAN_BONUS = 0.5; // clean race bonus: +50% for no penalties/contact

export const GRINDS = [
  {
    id: 'wtc800', name: 'World Touring Car 800', track: 'sardegna', layout: 'Road Track A',
    payout: 485000, minutes: 27, pp: 800, tyres: 'Racing',
    car: 'porsche919', alt: ['ts050'],
    why: 'The most consistent grind, according to current guides. Win clean and it pays 727,500 Cr. The AI is beatable once you can hold a clean race.',
    how: 'Detune a Gr.1 car to exactly 800 PP with the power restrictor and ballast. Run Racing Hard tyres and use the fuel map to make the strategy work. Pit when the race strategy says to, and keep it clean.',
    verified: 'Update 1.40+ (Spec II) era guide. Check the in-game payout.',
  },
  {
    id: 'wtc600tokyo', name: 'World Touring Car 600', track: 'tokyo', layout: 'Tokyo Expressway',
    payout: 550000, minutes: 32, pp: 600, tyres: 'Racing',
    car: 'gtrgt3', alt: ['rsr991'],
    why: 'Pays the most per race, up to about 825,000 Cr with the clean bonus. It starts wet and dries out, so it is harder to win every time.',
    how: 'A 600 PP Gr.3 car with full wets in the bag. Switch to slicks as the line dries. That call wins or loses the race.',
    verified: 'Top-end figure from current guides. Check the in-game payout.',
  },
  {
    id: 'wtc600suzuka', name: 'World Touring Car 600 (new in 1.71)', track: 'suzuka', layout: 'Full course',
    payout: null, minutes: 30, pp: 600, tyres: 'Racing',
    car: 'f296gt3', alt: ['rsr991'],
    why: 'Added in Update 1.71 (Aug 2026) to World Circuits. Payout not yet confirmed by our sources.',
    how: 'Enter your observed payout. The calculator will rank it against the others.',
    verified: 'Unknown payout. Fill it in.',
  },
  {
    id: 'clubman600cat', name: 'European Clubman Cup 600 (new in 1.71)', track: 'catalunya', layout: 'GP (no chicane)',
    payout: null, minutes: 15, pp: 600, tyres: 'Sports',
    car: 'caymangt4', alt: [],
    why: 'New in 1.71. Short race. Fill in the payout to see if it beats WTC on credits per hour.',
    how: 'Enter your observed payout.',
    verified: 'Unknown payout. Fill it in.',
  },
  {
    id: 'fishermans', name: 'Dirt Champions (Fisherman\'s Ranch)', track: null, layout: 'Fisherman\'s Ranch',
    payout: null, minutes: 6, pp: null, tyres: 'Dirt',
    car: 'evo', alt: ['impreza22b'],
    why: 'Once claimed about 10,000 Cr per minute, but an older patch cut it heavily. Verify before you invest time.',
    how: 'Rally event: AWD and dirt tyres.',
    verified: 'Possibly nerfed. Fill in the payout.',
  },
];

// Ways to earn that aren't repeat races. Each is a roadmap checklist item too.
export const BOOSTERS = [
  { id: 'daily', name: 'Daily Workout', what: 'Drive 42.195 km on any day for a daily roulette ticket. Do it while grinding.', value: 'Occasional jackpot: cars, engines, big credits.' },
  { id: 'weekly', name: 'Weekly Challenges', what: 'Rotating weekly objectives with tickets and occasional invitations.', value: 'Engine swap and invitation tickets you can\'t buy.' },
  { id: 'ce', name: 'Circuit Experience golds', what: 'Every sector plus the full lap at gold. Pays credits and teaches you each track.', value: 'A big one-time pile of credits and the best track-learning tool in the game.' },
  { id: 'missions', name: 'Missions', what: 'Finish every mission set.', value: 'Cars and credits.' },
  { id: 'licences', name: 'Licences all gold', what: 'B → A → IB → IA → S, all gold.', value: 'Cars and the skills Sport Mode needs.' },
  { id: 'clean', name: 'Clean race bonus', what: 'No penalties, no contact.', value: '+50% on every race. The biggest multiplier you control.' },
];
