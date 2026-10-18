// Wheel Lab: GT7 has only two steering FFB sliders, Force Feedback Max Torque
// and Force Feedback Sensitivity (1–10). The rest lives on the wheel base.
// The sources disagree, so these are starting points plus a method to find
// your own. Sources: GTPlanet (post-1.15 GT DD Pro), Fanatec forum,
// Coach Dave Academy, dg-edge, simracingsetup, Logitech's GT7 guide.

export const BASES = [
  {
    id: 'fanatec-dd', name: 'Fanatec GT DD Pro / CSL DD (direct drive)', kind: 'Direct drive',
    ingame: { torque: '8–10', sens: '1' },
    base: [['SEN', 'AUTO'], ['FF', '100'], ['FFS', 'PEAK'], ['NDP', '35–50'], ['NFR', '5–15'], ['NIN', '0'], ['INT', '3'], ['FEI', '80–100'], ['FOR / SPR / DPR', '100']],
    notes: 'The most common post-1.15 recipe is base FF 100 and in-game Max Torque 10, Sensitivity 1, then tame it with NDP (damping). Fanatec\'s older official baseline was Max Torque 5. Many 8 Nm owners found that weak and moved to 8.',
  },
  {
    id: 'fanatec-podium', name: 'Fanatec Podium DD1 / DD2', kind: 'High-torque direct drive',
    ingame: { torque: '5–7', sens: '1' },
    base: [['SEN', 'AUTO'], ['FF', '60–80'], ['FFS', 'PEAK'], ['NDP', '30–40'], ['NFR', '5'], ['INT', '3'], ['FEI', '100']],
    notes: 'Huge torque headroom: lower in-game Max Torque so the forces stay realistic and avoid oscillation on straights.',
  },
  {
    id: 'logitech-rs50', name: 'Logitech RS50 / G PRO (direct drive)', kind: 'Direct drive',
    ingame: { torque: '10', sens: '1' },
    base: [['Logitech G HUB / on-wheel', 'Use Logitech\'s GT7 profile'], ['TRUEFORCE', 'Off or low']],
    notes: 'Logitech\'s own G PRO recommendation is Max Torque 10, Sensitivity 1. Coach Dave runs higher sensitivity on the RS50, but that is a minority choice.',
  },
  {
    id: 'thrustmaster-tgt', name: 'Thrustmaster T-GT II / T248 / T300', kind: 'Belt / hybrid',
    ingame: { torque: '4–6 (T248) · 10 + base strength down (T-GT II)', sens: '1–4' },
    base: [['Wheel FFB strength', '25–75% to taste (T-GT II)']],
    notes: 'T248: above 4–5 torque introduces clipping. T-GT II: one approach is torque 10, sensitivity 1, and turn the overall strength down on the wheel until corners feel right.',
  },
  {
    id: 'logitech-g923', name: 'Logitech G923 / G29', kind: 'Gear-driven',
    ingame: { torque: '4–5', sens: '2–4' },
    base: [['TRUEFORCE', 'Off (drowns detail)']],
    notes: 'Above 5 torque clips on the G923. Gear-driven wheels tolerate sensitivity 2–4 without oscillating.',
  },
];

export const METHOD = [
  'Pick a reference: Gr.3 car you know, a track you know (Suzuka or Spa), dry.',
  'Set Sensitivity to 1. Raise Max Torque until the wheel clips (goes numb at peak load in fast corners), then back off one notch.',
  'Only then add Sensitivity, one step at a time, until you start to feel oscillation on straights or kerbs. Back off one.',
  'Direct drive oscillating on straights? Add base damping (NDP) before touching the in-game sliders.',
  'Test in a high-downforce car (Gr.1) at a fast corner (130R, Blanchimont). If it\'s violent or oscillates, reduce torque for that class.',
  'Write your final numbers in the notes below. They\'re saved on this device.',
];

export const PEDALS = [
  { t: 'Calibrate the travel', d: 'Run the wheel base\'s pedal calibration first, then GT7\'s. Full travel should read 0–100% with no dead spots.' },
  { t: 'Load-cell brake: set max force to a firm but sustainable push', d: 'If 100% needs your whole leg, you\'ll never hit it consistently. If it takes no effort, you\'ll lock up. Aim for a push you can repeat every corner for an hour.' },
  { t: 'Small brake deadzone at the top', d: 'A couple of percent stops the brake dragging when your foot rests on it.' },
  { t: 'Throttle curve', d: 'A linear throttle is the honest choice. A slightly progressive curve (softer at the start) helps powerful RWD cars.' },
  { t: 'Assists for wheel drivers', d: 'ABS Default (most fast drivers keep it), TCS 0–1 depending on the car, ASM off, countersteer assistance off, driving line off once learned.' },
  { t: 'Rotation', d: 'Set the base to its maximum/auto rotation and let GT7 apply each car\'s real steering lock (soft lock).' },
];

export const SEATING = [
  'Wheel centre at chest height. Arms bent about 100–120° at the elbow with hands at quarter to three.',
  'Pedals: knee still slightly bent at full brake. A locked knee can\'t modulate.',
  'Cockpit view, seat moved forward and low enough to see apexes. Lower the wheel model if it blocks the view.',
  'Screen as close as practical and centred on your eyeline, so the horizon sits at eye height.',
];
