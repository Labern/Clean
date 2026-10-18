// Tuning Lab: what each setting does, plus a symptom → fix solver.

export const SETTINGS = [
  { id: 'tyres', name: 'Tyres', what: 'The biggest single change. Comfort < Sports < Racing; Hard > Medium > Soft in life, Soft > Hard in grip.', tip: 'Check the event\'s tyre rule first: it often decides the car.' },
  { id: 'height', name: 'Ride Height', what: 'Lower = lower centre of gravity and better aero, but bottoming out on bumps and kerbs.', tip: 'Raise it 5–10 mm for the Nordschleife and Bathurst.' },
  { id: 'springs', name: 'Springs (Natural Frequency)', what: 'Stiffer = sharper response, less body roll, less grip on bumps.', tip: 'Stiffer front → understeer. Stiffer rear → oversteer.' },
  { id: 'dampers', name: 'Dampers (Compression/Extension)', what: 'Control how fast the car moves on its springs.', tip: 'Soft compression helps over kerbs. Soft extension helps keep tyres on the road.' },
  { id: 'arb', name: 'Anti-Roll Bars', what: 'Resist body roll. The quickest balance tool you have.', tip: 'Softer front → more front grip (less understeer). Softer rear → more rear grip (less oversteer).' },
  { id: 'camber', name: 'Camber', what: 'Tilts the tyre so it stays flat when the car rolls in a corner.', tip: 'More negative = more cornering grip, less braking/traction.' },
  { id: 'toe', name: 'Toe', what: 'Points the wheels in or out.', tip: 'Front toe-out sharpens turn-in. Rear toe-in adds stability.' },
  { id: 'lsd', name: 'Limited Slip Differential', what: 'Initial, Acceleration Sensitivity, Braking Sensitivity.', tip: 'Higher acceleration → more traction, more exit understeer. Higher braking → more stable entry, less rotation.' },
  { id: 'aero', name: 'Downforce', what: 'More downforce = more grip in fast corners, more drag on straights.', tip: 'Front/rear balance: more rear for stability, more front for turn-in.' },
  { id: 'brakebal', name: 'Brake Balance', what: 'Adjustable even under BoP in Sport Mode.', tip: 'Rearward helps rotation (careful), forward is stable.' },
  { id: 'gearing', name: 'Transmission', what: 'Final drive and individual ratios.', tip: 'Top gear should just reach the limiter at the end of the longest straight with a tow.' },
  { id: 'pp', name: 'Performance Points & Ballast', what: 'PP caps events. The power restrictor and ballast let you dial a car down exactly.', tip: 'Place ballast to fix balance (rear for traction, front for turn-in).' },
];

export const SOLVER = [
  {
    id: 'u-entry', symptom: 'Understeer on corner entry', side: 'entry',
    fixes: ['Trail-brake more (driver first)', 'Brake balance one click rearward', 'Soften front anti-roll bar', 'Add front downforce', 'Lower LSD braking sensitivity'],
  },
  {
    id: 'u-mid', symptom: 'Understeer mid-corner', side: 'mid',
    fixes: ['Slow your hands. Less steering often means more grip', 'Soften front anti-roll bar / stiffen rear', 'Add front camber', 'Lower front ride height slightly'],
  },
  {
    id: 'u-exit', symptom: 'Understeer on exit (pushes wide on throttle)', side: 'exit',
    fixes: ['Throttle later or more gradually', 'Lower LSD acceleration sensitivity', 'Soften rear springs', 'Shift ballast forward'],
  },
  {
    id: 'o-entry', symptom: 'Oversteer on entry (rear steps out braking)', side: 'entry',
    fixes: ['Less trail brake, release more gradually', 'Brake balance forward', 'Raise LSD braking sensitivity', 'Add rear downforce', 'More rear toe-in'],
  },
  {
    id: 'o-mid', symptom: 'Oversteer mid-corner', side: 'mid',
    fixes: ['Don\'t lift abruptly. Hold a little throttle', 'Soften rear anti-roll bar', 'Add rear downforce'],
  },
  {
    id: 'o-exit', symptom: 'Oversteer on exit (power oversteer / wheelspin)', side: 'exit',
    fixes: ['Throttle more gradually (pedal curve)', 'Raise TCS one step', 'Raise LSD acceleration sensitivity', 'Soften rear springs/dampers', 'Taller 2nd/3rd gear'],
  },
  {
    id: 'kerbs', symptom: 'Car bounces/unsettles over kerbs and bumps', side: 'any',
    fixes: ['Softer compression damping', 'Raise ride height', 'Softer springs'],
  },
  {
    id: 'straight', symptom: 'Slow on the straights', side: 'any',
    fixes: ['Reduce downforce', 'Check gearing reaches the limiter', 'Better exit from the corner before'],
  },
];
