// Beyond the Apex: Polyphony's official GT7 driving + engineering manual,
// each concept paraphrased (never copied) and pinned to real corners in this
// app's track guides. `src` is the article path under BASE; `corners` are
// indices into that track's `corners` array (tests check every reference).
export const APEX_BASE = 'https://www.gran-turismo.com/us/gt7/apex';

export const APEX_PARTS = [
  { id: 'start', title: 'Getting Started', kicker: 'YAM\'s advice + in-game settings' },
  { id: 'dynamics', title: 'Vehicle Dynamics', kicker: 'Engineering for automotive' },
  { id: 'mech', title: 'Mechanisms', kicker: 'How the hardware works' },
  { id: 'tune', title: 'Tuning & Settings', kicker: 'Settings for specific situations' },
];

export const APEX = [
  // ── Getting Started ────────────────────────────────────
  {
    id: 'width', part: 'start', title: 'Know the Width of Your Car',
    src: '/how_to_get_started/advice_for_beginners/02', article: 'Advice for Beginners · Getting to Know the Width of Your Car',
    idea: [
      'A wide arc is a fast arc. Out-in-out only works if you actually reach both edges, and most new drivers leave half a car width on the table at turn-in, apex and exit because they don\'t know where their wheels are.',
      'The manual\'s exercise: switch to the chase camera, drive with the white edge line under the car, and learn exactly what "wheels on the line" looks like from your seat. Then do it from the view you race in.',
    ],
    points: ['Every metre of width you use is radius you gain', 'Learn wheel position from your race camera, not by guessing', 'Touch the kerb, don\'t straddle the grass'],
    lesson: 'line', widget: 'line',
    demos: [
      { track: 'suzuka', corners: [1], title: 'Use every edge through the S Curves', watch: 'Each S is a change of direction. If you don\'t clip the inside kerb, you can\'t reach the far side for the next one, and the whole sequence collapses into one slow, tight line.', drill: 'Five laps with only one goal: left wheels on the left kerb, right wheels on the right, in rhythm. Ignore the lap time.' },
      { track: 'brands', corners: [0], title: 'Track out fully at Paddock Hill', watch: 'The exit drops away and drifts left. Drivers who don\'t trust their width lift here; the car has room all the way to the exit kerb.', drill: 'Chase cam for three laps, note where the kerb sits on screen, then repeat from cockpit.' },
    ],
  },
  {
    id: 'markers', part: 'start', title: 'Braking Markers and a Rule to React',
    src: '/how_to_get_started/advice_for_beginners/03', article: 'Advice for Beginners · Setting Track Markers / Learning How to Be Precise',
    idea: [
      'A braking point needs a landmark: distance boards, the start of a kerb, a marshal post, a gap in a stand. Anything fixed will do, and real drivers walk the track looking for them.',
      'Finding a marker isn\'t enough, because where it sits on screen depends on your view. The manual\'s fix is a personal rule for when to react. The author brakes at the instant the board vanishes off the edge of the screen. Same rule every lap means you can move the point by small, measurable steps.',
      'If you stop short, brake just after your marker next time. If you overshoot, treat the point as before it.',
    ],
    points: ['Pick a fixed landmark for every braking zone', 'React by a rule (e.g. the moment it leaves the screen)', 'Adjust in small steps: half a board at a time'],
    lesson: 'vision', widget: 'brake',
    demos: [
      { track: 'fuji', corners: [1], title: 'The manual\'s own example: Coca-Cola Corner', watch: 'Beyond the Apex demonstrates the "brake when the board disappears" rule on the approach to Coca-Cola Corner. Short braking zone, so precision shows up instantly on the delta.', drill: 'Ten laps braking exactly as the chosen board leaves the screen. Only once you\'re consistent, move half a board later.' },
      { track: 'fuji', corners: [0], title: 'The big stop at TGR Corner', watch: 'The longest straight in the game ends here and the boards count you down. Different speed, same rule: one board, one moment, every lap.', drill: 'Use the 100 m board. Note where you stop relative to the apex and move one step at a time.' },
      { track: 'monza', corners: [0], title: 'Rettifilo: boards at 300 km/h', watch: 'At this speed a tenth of a second is 8 m. A rule-based reaction is the only way to be repeatable into the first chicane.', drill: 'Pick the 150 or 100 board and log where you brake for five laps. Spread over 10 m means you\'re reacting, not following a rule.' },
    ],
  },
  {
    id: 'turnin', part: 'start', title: 'Turn-in Timing: Full Lock at the Apex',
    src: '/how_to_get_started/advice_for_beginners/05', article: 'Advice for Beginners · Taking Corners',
    idea: [
      'Steer in gradually from the outside and keep adding lock until the clipping point. That\'s where the steering angle should peak. After the apex you only unwind.',
      'The diagnosis is simple. Reaching the inside too early means you turned in too early. Not reaching it by mid-corner means you turned in too late. Fix the turn-in point first; speed and everything else come after.',
      'GT7\'s yellow corner indicators help: link one to the next and the line appears.',
    ],
    points: ['Peak steering = apex', 'Inside too soon → turn in later', 'Can\'t reach the inside → turn in earlier'],
    lesson: 'line', widget: 'line',
    demos: [
      { track: 'spa', corners: [0], title: 'La Source: the early turn-in trap', watch: 'A hairpin straight after the start where everyone turns in too soon, hits the inside early and runs wide up the hill. Max lock should arrive at the apex kerb, not before.', drill: 'Turn in a car-length later each lap until you reach the apex with lock still building. Watch the exit speed into Eau Rouge.' },
      { track: 'suzuka', corners: [5], title: 'The Hairpin: steering peak as a check', watch: 'Slow and symmetrical, so it\'s the cleanest place to feel whether peak steering lands at the apex. Early peak = you\'ll be unwinding and re-adding lock.', drill: 'Use the Logger replay: the steering trace should rise once, peak at the apex, fall once.' },
      { track: 'laguna', corners: [0], title: 'Andretti Hairpin: late and patient', watch: 'Double-apex shape. Turning in too early for the first part ruins the second. Wait.', drill: 'Run the corner as one late apex for five laps, then as a double apex, and compare exits.' },
    ],
  },
  {
    id: 'vision', part: 'start', title: 'Look Ahead, Link the Corners',
    src: '/how_to_get_started/advice_for_beginners/05', article: 'Advice for Beginners · Taking Corners',
    idea: [
      'Your eyes should always be one step ahead of the car: braking marker, then the steering marker, then the clipping point, then the exit, then the next corner, moving on before you arrive.',
      'Linking each yellow corner indicator to the next shows the line through a whole sequence, not just one bend.',
    ],
    points: ['Eyes move before the car does', 'Marker → turn-in → apex → exit → next', 'Sequences are one line, not several corners'],
    lesson: 'vision',
    demos: [
      { track: 'nordschleife', corners: [0, 1], title: 'Hatzenbach to Hocheichen', watch: 'A string of blind, narrow direction changes. If you look at the corner you\'re in, you\'ll arrive at each one late and on the wrong side.', drill: 'Say the next corner\'s name out loud as you pass each apex. Vision follows.' },
      { track: 'bathurst', corners: [6], title: 'Skyline and The Esses', watch: 'Over the crest you can\'t see the road. Commit to a reference you saw before the crest and look for where the road reappears.', drill: 'Pick a tree or sign above the crest as the turn-in reference and use it every lap.' },
    ],
  },
  {
    id: 'throttle', part: 'start', title: 'Keep the Throttle Down Longest',
    src: '/how_to_get_started/in_game/01', article: 'In-game settings · General Principles',
    idea: [
      'The manual\'s core principle: the driver who spends the most time at full throttle wins. Top speed at the end of a straight is decided by the exit of the corner before it, so the goal is getting back on power earlier.',
      'Think about the whole lap, not one corner. Losing a little at a slow corner to gain a better exit is almost always a net win.',
      'PP is built from top speed, acceleration and engine rpm at set speeds. Spend it where the track needs it: power for long straights, response for twisty circuits.',
    ],
    points: ['Exit speed is straight-line speed', 'Judge the lap, not the corner', 'Spend PP on what this track rewards'],
    lesson: 'priority',
    demos: [
      { track: 'lemans', corners: [3], title: 'Tertre Rouge feeds the Mulsanne', watch: 'Several kilometres of straight follow. One km/h more on exit here is worth more than anything you gain on entry.', drill: 'Brake earlier, apex later, flat sooner. Compare the speed trap at the first chicane.' },
      { track: 'monza', corners: [6], title: 'Parabolica sets up the main straight', watch: 'Long, opening corner. The earlier the throttle is pinned, the faster you are all the way to the line and into Turn 1.', drill: 'Find the point you can go 100% throttle and move it earlier by a metre at a time.' },
      { track: 'spa', corners: [0, 1], title: 'La Source to Kemmel', watch: 'A slow hairpin before the longest flat-out section of the lap. A compromised entry costs nothing; a compromised exit costs you all the way up the Kemmel straight.', drill: 'Sacrifice entry speed at La Source for three laps and watch the delta at Les Combes.' },
    ],
  },
  {
    id: 'assists', part: 'start', title: 'Assists as a Coach, Not a Crutch',
    src: '/how_to_get_started/using_driver_assistance/02', article: 'Using Driving Assistance Settings ① Braking / ② Car Control',
    idea: [
      'The braking aids teach the stop: Braking Area shows where to brake, Braking Indicator shows how hard, Suggested Gear shows what gear to be in. Use them to learn a track, then turn them off.',
      'Traction control has levels. The manual suggests starting around the middle and lowering it as you get comfortable, because a tyre makes its best grip with a little slip, and too much intervention cuts that.',
      'ABS: leave it on default while learning. Countersteering assistance and ASM help prevent spins by braking individual wheels (inside rear for understeer, outside front for oversteer), but they also cover up mistakes you need to feel.',
    ],
    points: ['Braking aids teach a track, then go off', 'TCS: start mid, step down as your foot improves', 'ASM fixes slides by braking single wheels'],
    lesson: 'throttle',
    demos: [
      { track: 'tsukuba', corners: [3], title: 'Learn a stop with Braking Area on', watch: 'Short lap, hard stop. The Braking Area guide shows where you should brake. Do ten laps with it, then switch it off and hit the same point.', drill: 'Aid on: 10 laps. Aid off: 10 laps. Compare the times in the Logger.' },
      { track: 'interlagos', corners: [8], title: 'Junção: step TCS down here', watch: 'Uphill exit onto the longest flat section. Too much TCS cuts power; too little spins the rear. The right level shows on the speed up the hill.', drill: 'Drop TCS one step every five laps until the exit becomes untidy, then go back one.' },
    ],
  },
  {
    id: 'etiquette', part: 'start', title: 'Race Etiquette: Limits, Rejoins, Yielding',
    src: '/how_to_get_started/race_etiquette/01', article: 'Race Etiquette · Ensuring safe and enjoyable races',
    idea: [
      'The white lines are the track. All four wheels over them is a penalty in most races, and cutting a corner while battling is the classic way to get one.',
      'If you go off, rejoin without blocking or hitting anyone behind you. Look first. A slow rejoin costs less than a penalty and an angry rival.',
      'When a faster car arrives, yield smoothly and predictably. Don\'t swerve or brake unexpectedly.',
    ],
    points: ['Keep two wheels inside the white lines', 'Look before you rejoin', 'Yield predictably, never suddenly'],
    lesson: 'slipstream',
    demos: [
      { track: 'spa', corners: [11], title: 'The Bus Stop: don\'t cut it', watch: 'Late braking in a fight makes cutting the chicane tempting. That\'s a penalty, and in Sport Mode an SR hit.', drill: 'Practice the defensive line here with all four wheels inside the white lines, every lap.' },
      { track: 'redbullring', corners: [0], title: 'Turn 1, lap 1', watch: 'Uphill, tight, and the whole grid arrives at once. This is where rejoins and contact happen.', drill: 'In Sport races, brake a marker early on lap 1 and pick off the cars that overshoot.' },
    ],
  },

  // ── Vehicle Dynamics ───────────────────────────────────
  {
    id: 'slip', part: 'dynamics', title: 'Tyres Grip Through Slip',
    src: '/engineering_for_automotive/vehicle_performance/01', article: 'Vehicle Performance · 2-1 Tire Dynamics',
    idea: [
      'A tyre makes cornering force by running at a slip angle: the direction it points differs slightly from where it travels. Force rises steeply with small angles (that slope is the cornering power) and then flattens and saturates. Past the peak, more steering only adds scrub.',
      'Braking or driving uses up some of that same grip. The limit is an envelope the manual draws as an oval rather than a perfect circle, because a tyre can usually take more force in one direction than the other.',
    ],
    points: ['Grip peaks at a small slip angle', 'Past the peak, more steering = less turn', 'Braking + cornering share one envelope (an oval)'],
    lesson: 'circle', widget: 'circle',
    demos: [
      { track: 'suzuka', corners: [7], title: 'Spoon: ride the edge of the oval', watch: 'Long, double-apex left that you enter still braking. Brake force has to come out as cornering force goes in, staying on the edge of the envelope the whole way.', drill: 'Trail the brake to the first apex. If the front washes out, you\'re asking for both at 100%.' },
      { track: 'laguna', corners: [6], title: 'Rainey Curve: too much steering', watch: 'Downhill and off-camber after the Corkscrew. Adding lock when the front starts to slide makes it slide more. Unwind slightly and the grip comes back.', drill: 'When it understeers, take a few degrees of lock out, don\'t add it. Feel the force return through the wheel.' },
    ],
  },
  {
    id: 'balance', part: 'dynamics', title: 'Understeer, Neutral, Oversteer',
    src: '/engineering_for_automotive/vehicle_performance/02', article: 'Vehicle Performance · 2-2 Steady-state Circular Driving',
    idea: [
      'Drive a constant circle and go faster. An understeering car needs more steering as speed rises, a neutral one the same, an oversteering one less. That\'s the definition, and it\'s about speed, not just behaviour.',
      'An oversteering car has a critical speed above which it becomes unstable. That\'s why road cars are designed to understeer slightly.',
    ],
    points: ['US: more lock as speed rises', 'OS: less lock as speed rises, unstable past a critical speed', 'Long constant corners show the car\'s true balance'],
    lesson: 'weight', widget: 'weight',
    demos: [
      { track: 'suzuka', corners: [8], title: '130R: balance at speed', watch: 'Near-constant radius, very fast. A car that\'s neutral at 150 km/h can be oversteery here. The lock you need tells you the balance.', drill: 'Hold a fixed throttle through 130R and note whether you add or remove lock across the corner.' },
      { track: 'monza', corners: [6], title: 'Parabolica: understeer you can measure', watch: 'Long, constant then opening. Add throttle and an understeering car pushes wide. The amount of lock you need to hold the line is the reading.', drill: 'Compare two cars (FR and MR) at the same speed and feel which one needs more lock.' },
    ],
  },
  {
    id: 'yaw', part: 'dynamics', title: 'Turning Takes Time: the Yaw Sequence',
    src: '/engineering_for_automotive/vehicle_performance/03', article: 'Vehicle Performance · 2-3 A Car\'s Response to Changes in Steering Angle',
    idea: [
      'When you steer, the car doesn\'t turn instantly. First the front tyres build slip angle, which starts the car rotating. Only then do the rears build slip angle and the car settles into a steady turn. There\'s a delay at every step.',
      'In fast direction changes you have to steer slightly ahead of the car, with smooth inputs that give each step time to happen. Jerky inputs arrive before the car has caught up with the last one.',
    ],
    points: ['Front slip → yaw → rear slip → steady', 'Steer slightly ahead in quick changes', 'Smooth inputs let the sequence finish'],
    lesson: 'alien',
    demos: [
      { track: 'spa', corners: [1], title: 'Eau Rouge / Raidillon', watch: 'Left, right, left in a second while compressing then cresting. If your inputs are late, the car is still rotating left when you need right.', drill: 'Make the steering smaller and earlier. The car turns when the rears catch up, not when you steer.' },
      { track: 'lemans', corners: [9], title: 'The Porsche Curves', watch: 'Fast, linked direction changes where an abrupt input unsettles the rear on the next turn-in.', drill: 'Use the Logger steering trace: aim for smooth curves, not spikes.' },
      { track: 'suzuka', corners: [1], title: 'The S Curves', watch: 'Rhythm is the yaw sequence in action. Late inputs carry over into the next corner and the error grows.', drill: 'Turn in a touch earlier and gentler for each S. If the last one feels rushed, the first was late.' },
    ],
  },
  {
    id: 'load', part: 'dynamics', title: 'Load Transfer Costs Grip',
    src: '/engineering_for_automotive/vehicle_performance/05', article: 'Vehicle Performance · 2-5 Body Roll and Vehicle Motion',
    idea: [
      'Grip rises with load but less than proportionally (load sensitivity). Shifting load from one tyre to another always loses more grip from the light tyre than the heavy one gains, so the pair makes less total force.',
      'Whichever end transfers more load across the car in a corner loses grip first. More front load transfer means understeer; more at the rear means oversteer. Roll stiffness, roll centre height and track width decide where it goes.',
    ],
    points: ['Moving load always loses total grip', 'More front transfer → understeer', 'Crests unload, compressions load'],
    lesson: 'weight', widget: 'weight',
    demos: [
      { track: 'laguna', corners: [5], title: 'The Corkscrew', watch: 'Blind crest, then a steep drop through a left-right. The car is light over the top: brake or turn there and the tyres have almost nothing to give.', drill: 'Do your braking before the crest and stay off the brake as it drops. Let the compression load the tyres.' },
      { track: 'nordschleife', corners: [2], title: 'Flugplatz', watch: 'A crest the car gets light over. Any steering or braking while unloaded goes straight into a slide on landing.', drill: 'Straighten the wheel over the crest and pick the line back up once the car lands.' },
      { track: 'spa', corners: [1], title: 'Eau Rouge compression', watch: 'The dip at the bottom loads the car and adds grip, which is why it can be taken flat. The crest at the top takes it away.', drill: 'Feel where the wheel goes heavy (grip) and light (none) in force feedback.' },
    ],
  },
  {
    id: 'rear', part: 'dynamics', title: 'Performance Lives in the Rear Tyres',
    src: '/engineering_for_automotive/vehicle_performance/07', article: 'Vehicle Performance · 2-7 What Constitutes a High-Performance Car?',
    idea: [
      'More rear grip makes the car respond faster and with less lag, at the cost of a little understeer. More front grip does the opposite: sharper rotation but slower, laggier response.',
      'The manual\'s order for setup: secure enough rear grip first, then tune the front-rear balance. A car you can trust at the rear lets you commit.',
    ],
    points: ['Rear grip first, balance second', 'More rear grip = faster response, slight understeer', 'Confidence is grip you can use'],
    lesson: 'alien',
    demos: [
      { track: 'nordschleife', corners: [3], title: 'Schwedenkreuz', watch: 'Fast, blind, downhill. Only possible at full commitment if the rear is planted.', drill: 'If you lift here, add rear stability (wing, softer rear bar) before chasing lap time elsewhere.' },
      { track: 'suzuka', corners: [8], title: '130R', watch: 'A nervous rear makes you lift. A stable one lets you stay flat.', drill: 'Test one setup change at a time and watch the minimum speed in the Logger.' },
    ],
  },

  // ── Mechanisms ─────────────────────────────────────────
  {
    id: 'layout', part: 'mech', title: 'FR, FF, MR, RR, 4WD',
    src: '/review_mechanism/packaging/02', article: 'Basic Specs · Drivetrains and Weight Distribution',
    idea: [
      'Where the engine sits and which wheels drive decide how a car behaves. FR is the balanced classic. FF asks the front tyres to steer and drive at the same time. MR carries its mass in the middle for low yaw inertia and quick rotation. RR has huge traction but a rear that lets go suddenly. 4WD spreads the drive and exits hard.',
      'Each needs a different technique: patience on throttle with FF, care at turn-in with MR, respect for weight transfer with RR.',
    ],
    points: ['FF: front shares steering and drive', 'MR: rotates quickly, snaps quicker', 'RR: traction monster, abrupt at the limit'],
    lesson: 'throttle',
    demos: [
      { track: 'tsukuba', corners: [3, 5], title: 'Same hairpin, five drivetrains', watch: 'Short, tight and slow: Tsukuba exposes drivetrain differences more than any other track. The hairpin exits show traction; the Final Corner shows balance.', drill: 'Run the same two corners in an FF, FR, MR, RR (911) and 4WD car. Write down where each wants you to brake and when it lets you throttle.' },
      { track: 'brands', corners: [1], title: 'Druids: rotation on entry', watch: 'Tight hairpin with uphill braking into it. An MR car rotates eagerly, an FF car pushes, an RR car goes light at the front.', drill: 'Compare entry speeds across layouts and feel the yaw inertia.' },
    ],
  },
  {
    id: 'lsd', part: 'mech', title: 'Differentials and LSDs',
    src: '/review_mechanism/drivetrain/02', article: 'Turning Power into Speed · The Differential and LSD',
    idea: [
      'An open differential lets the wheels turn at different speeds, which you need in a corner. But it sends power to the wheel with the least grip, so the unloaded inside wheel spins on exit.',
      'A limited-slip differential locks the wheels together to some degree. Torque-sensitive (mechanical), viscous and electronically controlled types do it differently. More locking means better traction but a car that resists turning.',
    ],
    points: ['Open diff: inside wheel spins away the power', 'LSD lock: traction vs rotation', 'Accel lock = exits, decel lock = entries'],
    lesson: 'throttle',
    demos: [
      { track: 'tsukuba', corners: [0], title: 'First hairpin exit', watch: 'Tight right with the inside wheel unloaded. With too little locking it lights up; with too much the car pushes wide on throttle.', drill: 'Raise acceleration sensitivity in steps of 5 and note when exit traction stops improving.' },
      { track: 'montreal', corners: [4], title: 'L\'Épingle', watch: 'Heavy braking into a very slow hairpin. Decel lock decides whether the car rotates or pushes straight on.', drill: 'Lower deceleration lock until the car rotates on entry without stepping out.' },
    ],
  },
  {
    id: 'brakes', part: 'mech', title: 'Brakes Turn Speed into Heat',
    src: '/review_mechanism/brakes/01', article: 'Thermal Exchangers that Reduce Speed · Construction and Principles',
    idea: [
      'Brakes don\'t remove speed, they convert kinetic energy into heat. Disc brakes win because the disc sits in the airflow and sheds that heat; ventilated discs do it faster, and brake fluid is designed not to boil.',
      'Kinetic energy rises with the square of speed: the stop from 330 km/h carries far more energy than the stop from 200. Big stops after long straights are where the brakes work hardest.',
    ],
    points: ['Energy scales with speed squared', 'Hardest stops follow the longest straights', 'Brake balance shifts grip front-rear'],
    lesson: 'braking', widget: 'brake',
    demos: [
      { track: 'lemans', corners: [6], title: 'Mulsanne Corner', watch: 'One of the biggest single stops in the game. Threshold braking from top speed is where you learn the ABS and pedal feel on your wheel.', drill: 'On your G PRO, find the pedal pressure just short of ABS. Use it every lap and note the stopping point.' },
      { track: 'monza', corners: [0], title: 'Rettifilo', watch: 'A huge stop from very high speed into a slow chicane. The brake has to come off progressively as you turn.', drill: 'Hit the pedal hard, then release progressively into the first apex. Compare with a single flat press.' },
    ],
  },
  {
    id: 'aero', part: 'mech', title: 'Drag, Lift and Downforce',
    src: '/review_mechanism/aerodynamics/01', article: 'The Effect of Air on the Body · Air Resistance and Lift',
    idea: [
      'Above roughly 80 km/h air resistance dominates and it grows with the square of speed: double the speed, four times the drag. Top speed is where drag equals engine power.',
      'Shapes that slip through the air often generate lift, and reducing lift usually adds drag. Downforce gives you grip in fast corners and costs you top speed. Every setup is that trade.',
      'Front and rear downforce can be set separately. More front sharpens turn-in at speed; more rear calms oversteer.',
    ],
    points: ['Drag ∝ speed²', 'Downforce = fast-corner grip, paid for on the straights', 'Front vs rear wing tunes balance at speed'],
    lesson: 'tyres',
    demos: [
      { track: 'monza', corners: [2, 5], title: 'Monza: low wing wins', watch: 'Long straights, mostly slow chicanes. Downforce barely helps in the Roggia and only helps a little at Ascari; drag costs you everywhere.', drill: 'Run minimum rear wing, then +100, and compare the speed trap against the sector time through Ascari.' },
      { track: 'suzuka', corners: [1, 8], title: 'Suzuka: wing pays off', watch: 'The S Curves and 130R are fast corners where downforce adds real speed. The straights are short.', drill: 'Same test as Monza. The result flips, and that\'s the lesson.' },
    ],
  },

  // ── Tuning & Settings ──────────────────────────────────
  {
    id: 'circuit', part: 'tune', title: 'High-Speed Circuits vs Technical Courses',
    src: '/review_tuning_and_settings/advanced_settings/01', article: 'Settings for Specific Situations · High-Speed Circuits, Technical Courses',
    idea: [
      'Fast tracks: stiff and low for stability, but not so low the car can\'t absorb bumps. Stiff springs pair with slightly softer bars, and soft springs with stiffer bars. Some rear toe-in helps high-speed stability, and downforce should be as low as stability allows.',
      'Technical tracks: quick turn-in and strong drive off slow corners matter most. Gearing and suspension serve rotation and traction, not top speed.',
      'Gearing rule for both: top gear should just reach the redline at the end of the longest straight.',
    ],
    points: ['Fast: stable, low drag, rear toe-in', 'Technical: rotation + traction', 'Top gear hits redline at the end of the longest straight'],
    lesson: 'tyres', tool: ['#/tuning', 'Tuning Lab'],
    demos: [
      { track: 'lemans', corners: [6], title: 'Gear for the Mulsanne', watch: 'The longest straight on the calendar. If you hit the limiter before the braking zone, the gearing is short; if you never see the redline, it\'s long.', drill: 'Adjust the final drive until top gear just touches the redline at the braking point for Mulsanne Corner.' },
      { track: 'tsukuba', corners: [0, 3], title: 'Tsukuba: everything for the hairpins', watch: 'Short straights, slow hairpins. Shorter gearing and more rotation beat top speed here.', drill: 'Shorten the final drive until you\'re in 2nd for both hairpins without bouncing off the limiter.' },
    ],
  },
  {
    id: 'fixes', part: 'tune', title: 'Fixing Understeer and Oversteer by Phase',
    src: '/review_tuning_and_settings/advanced_settings/02', article: 'Settings for Specific Situations · Countering Understeer, Countering Oversteer',
    idea: [
      'First find where it happens: entry, apex or exit. The fixes are different for each.',
      'Entry understeer: help weight move to the front (softer front, damping that lets it pitch), less decel locking on the LSD, and on fast tracks more front downforce. Apex understeer: more negative camber at the front, less rear toe-in. Exit understeer in RWD: help the front, balance rear traction. In FWD, more LSD can help, but too much makes it worse.',
      'RWD cars oversteer most. Fix the phase it happens in, not the car as a whole.',
    ],
    points: ['Diagnose by phase: entry / apex / exit', 'Entry US → load the front, less decel lock', 'Change one thing at a time'],
    lesson: 'weight', tool: ['#/tuning', 'Tuning Lab solver'],
    demos: [
      { track: 'laguna', corners: [0], title: 'Andretti: entry understeer test', watch: 'Heavy braking downhill into a hairpin. If the car won\'t turn while you\'re still braking, it\'s entry understeer.', drill: 'Lower LSD deceleration lock by 5, test, then soften front springs one step. One change per run.' },
      { track: 'interlagos', corners: [8], title: 'Junção: exit oversteer test', watch: 'Uphill exit with power on. If the rear steps out as you add throttle, it\'s exit oversteer.', drill: 'Try lower acceleration lock, then a softer rear bar. Compare in the Logger.' },
    ],
  },
  {
    id: 'wet', part: 'tune', title: 'Wet Setup: Compliance Over Stiffness',
    src: '/review_tuning_and_settings/advanced_settings/03', article: 'Settings for Specific Situations · Wet Conditions, Gravel',
    idea: [
      'Less friction means less grip, so make the car compliant: softer springs, damping and bars so the tyres follow the surface. A stiff car in the wet lets go suddenly.',
      'Slightly less camber for a bigger contact patch under braking and acceleration. More downforce front and rear where it\'s adjustable.',
      'Tyre pressure is the quickest tool: a little higher in heavy rain to fight aquaplaning, a little lower in light rain for grip. Power delivery should favour smooth torque over peak, and the assists earn their keep.',
    ],
    points: ['Softer everything', 'More wing, less camber', 'Smooth torque beats peak power'],
    lesson: 'wet',
    demos: [
      { track: 'interlagos', corners: [0, 2], title: 'Interlagos in the rain', watch: 'The Senna S and Descida do Lago both have braking downhill. A stiff car locks and slides; a compliant one stays in line.', drill: 'Run the same car dry-setup vs soft wet-setup in a wet race and compare stopping points.' },
      { track: 'spa', corners: [1], title: 'Eau Rouge wet', watch: 'Compression then crest at speed. A soft setup keeps the tyres working over the crest.', drill: 'Find how much lift you need in the wet, then try a softer rear bar and see if you need less.' },
    ],
  },
];

export const apexById = Object.fromEntries(APEX.map((a) => [a.id, a]));
export const apexUrl = (a) => APEX_BASE + a.src;
// Concepts demonstrated at a given track, for the track guide.
export const apexForTrack = (tid) => APEX.flatMap((a) => a.demos.filter((d) => d.track === tid).map((d) => ({ a, d })));
