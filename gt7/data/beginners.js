// Start Here: the beginner course. Content only, no UI.
// Written for someone with no licences and no Gran Turismo history.
// Where a number or name could drift with a game patch, it is described generally.

export const BEGINNER = {
  intro: 'Gran Turismo 7 is a driving game built around real cars and real physics. You start with nothing but a little credit and a Café menu, and you grow into a driver who can race a full grid with confidence. This course starts from zero. It covers what the game is, how to control a car with a wheel or a controller, the physics that decide whether you go fast or spin into the gravel, and the habits that make the difference between a learner and a racer. Work through it in order. Each chapter ends with one thing to try in the game right now.',

  chapters: [
    {
      id: 'what-is-gt7',
      title: 'What Gran Turismo is',
      kicker: 'Chapter 1',
      minutes: 4,
      summary: 'Gran Turismo 7 is a simulator with a career wrapped around it, and most of what you do is driving real cars on real tracks to earn the money and rewards to buy better ones.',
      sections: [
        {
          h: 'A simulator with a game around it',
          p: [
            'Gran Turismo calls its driving model the Real Driving Simulator. The cars are modelled on their real counterparts, with weight, power, grip, tyres and suspension all affecting how they behave. The aim is that a car which is tail-happy in real life is also tail-happy in the game.',
            'That realism is the point of the series, but you do not need to understand it on day one. Every car handles differently, and the game teaches you the differences as you drive.'
          ]
        },
        {
          h: 'What you actually do',
          p: [
            'Most of your time is spent on the track. You race, you complete challenges, and you collect credits. Credits buy cars, tyres, upgrades and parts. Cars let you enter better races, which pay more credits. That loop is the whole game.',
            'Outside of racing you will spend time in menus. You choose which car to take out, set up the car, look at the dealerships, and track your progress through licences and missions.'
          ]
        },
        {
          h: 'How progress works',
          p: [
            'Progress comes from three things: licences, which prove your basic skill; events and missions, which give you reasons to drive specific cars on specific tracks; and money, which lets you buy more cars and tune them.',
            'You do not need to buy everything. Pick a car you enjoy, learn it properly, and move up from there. Learning one car well teaches more than driving ten badly.'
          ]
        }
      ],
      tips: [
        'Do not try to buy the fastest car first. A slower car you understand will teach you more.',
        'Lap times are a score, not a verdict. Consistency matters more than one fast lap.',
        'Read the race briefing before every event. Tyre rules and penalties are listed there.',
        'Turn off nothing yet. Learn the game with its default settings and change them later.'
      ],
      try: 'Start the game, open the Café, and read the first menu book page without buying anything.'
    },

    {
      id: 'controls',
      title: 'Controls: wheel, pedals and controller',
      kicker: 'Chapter 2',
      minutes: 6,
      summary: 'A wheel and pedals give you the most feedback, but the DualSense works well once you know its layout, and the same driving principles apply to both.',
      sections: [
        {
          h: 'Wheel and pedals (Logitech G PRO)',
          p: [
            'A direct-drive wheel like the G PRO transmits the road surface and the car’s behaviour straight into your hands. Set the wheel base to its maximum rotation and let GT7 apply each car\'s real steering lock automatically. A rally car and a Formula car then feel different, as they should. Wheel Lab has starting force-feedback settings for the G PRO.',
            'Pedals run clutch (if your set has one; GT7 shifts for you unless you choose a manual clutch), brake, throttle from left to right. Most drivers brake with the right foot, using the same foot for brake and throttle and rocking between them. Some drivers brake with the left foot, which frees the right foot for throttle alone. Either is valid. Pick one, and stick with it for a week before you change.'
          ]
        },
        {
          h: 'DualSense controller',
          p: [
            'On the DualSense, the right trigger (R2) is the throttle and the left trigger (L2) is the brake. The left stick steers. Learn to squeeze the triggers gently, because a sudden press on either one is the controller’s equivalent of stamping on a pedal.',
            'The controller gives less feedback than a wheel, so you will rely more on watching the car and the racing line. Vibration and adaptive trigger effects tell you a little about grip, but they are no substitute for experience.'
          ]
        },
        {
          h: 'Looking through the corner',
          p: [
            'Where you look decides where the car goes. Look at the exit of the corner, not the wall or the kerb in front of the car. Your hands follow your eyes, so a steady gaze produces steady steering.',
            'Look ahead to the next apex before you reach the current one. Drivers who look two corners ahead make smoother inputs, because they already know what is coming.'
          ]
        }
      ],
      tips: [
        'Set the wheel rotation to match the car, not the other way round.',
        'Squeeze the throttle and brake rather than stamping. Smooth inputs go faster than heavy ones.',
        'Keep your eyes on where you want to go, not on the nearest obstacle.',
        'If you use a controller, change the camera until you can see the next corner clearly.'
      ],
      try: 'Open the controls settings and set your steering rotation, then drive one lap of a short track and focus only on smooth throttle.'
    },

    {
      id: 'first-hour',
      title: 'Your first hour in GT7',
      kicker: 'Chapter 3',
      minutes: 6,
      summary: 'Your first session is about the Café, a first car, a few simple races, and learning to find your way around the menus and the world map.',
      sections: [
        {
          h: 'The Café and menu books',
          p: [
            'The Café is the early-game hub. It offers menu books, which are sets of tasks that unlock as you complete them. Early menu books walk you through the basics: getting a car, driving it, entering a race, and collecting your first rewards.',
            'Follow the menu books in order. They are designed to teach you the game as you go, and they hand out the credits you need to buy better tyres and cars.'
          ]
        },
        {
          h: 'Your first car and first races',
          p: [
            'The first car you get is for learning. Do not treat it as a permanent choice. Drive it through the early races and notice what it does at the limit: where it runs wide, where it spins, and where it grips.',
            'Your first races are short and cheap to enter. Finish them cleanly rather than chasing the win. Points and credits come from finishing, and a clean race tells you more than a risky one.'
          ]
        },
        {
          h: 'Menus and the world map',
          p: [
            'The menus are split into areas. Use the menu to choose your next event, check your car, visit a dealership, or look at your progress. The world map shows the locations you can visit and the events available there.',
            'Get in the habit of checking the event details before you enter. They tell you the car class, tyre rules, number of laps and any restrictions. Entering the wrong car is an easy mistake to make in the first few hours.'
          ]
        }
      ],
      tips: [
        'Finish the menu books in order. They are the game’s tutorial, and they pay you to complete them.',
        'Read the event details before you enter. Restrictions are listed there.',
        'Do not buy tyres or upgrades until you have a reason. Credits are scarce early on.',
        'If a race goes badly, leave it and try again. Practice is free.'
      ],
      try: 'Go to the Café, open the first available menu book, and complete one task from it before doing anything else.'
    },

    {
      id: 'grip-and-tyres',
      title: 'Car physics: grip and the tyre',
      kicker: 'Chapter 4',
      minutes: 8,
      summary: 'Each tyre has a small contact patch with the road, and that patch has a fixed amount of grip that you share between braking, accelerating and turning.',
      sections: [
        {
          h: 'The contact patch',
          p: [
            'All the forces on a car pass through four small patches of rubber, one per tyre. Each patch is roughly the size of a hand. Everything the car does, from braking to cornering to accelerating, has to happen through those four patches.',
            'If you remember one thing from this chapter, remember that the patch is small. Grip is limited, and it is the same grip whether you spend it braking, turning or accelerating.'
          ]
        },
        {
          h: 'The grip budget',
          p: [
            'Think of grip as a budget you spend on every input. Braking hard uses a lot. Turning hard uses a lot. Accelerating hard uses a lot. Asking for all three at once, which is what a panicky driver does, usually means one of them gets dropped and the car slides.',
            'Fast drivers do not use less grip. They blend it: as the brake comes off, the steering goes on, and as the steering comes off, the throttle goes on. The tyre is always working near its limit but never asked for more than it has. (The Academy\'s traction-circle diagram shows this in motion.)'
          ]
        },
        {
          h: 'Tyre compounds and heat',
          p: [
            'Tyres come in compounds. In GT7 there are three families, Comfort, Sports and Racing, from least to most grip, and each comes in Hard, Medium and Soft. Softer compounds grip more but wear faster. Intermediate and wet tyres are for wet or damp tracks, and using the wrong ones on a dry track or a wet one costs time quickly.',
            'Tyres also have a working temperature. Cold tyres grip poorly, especially in the first lap. Tyres that run too hot lose grip and wear faster. Warm them up gently, avoid abuse in the first corners, and watch for the car feeling different as the tyres come up to temperature.'
          ]
        }
      ],
      tips: [
        'Smooth inputs keep the tyres inside their grip budget. Sudden inputs overload them.',
        'Warm your tyres on the first lap. Do not try for a fast lap on cold rubber.',
        'Pick the compound for the race length and the track. Softer is not always faster over a long race.',
        'Use intermediates or wets when the track is damp. Dry tyres on a wet track are a slow way to learn.'
      ],
      try: 'In the first lap of any race, brake gently into one corner and feel how the car settles. Then do the same with a slightly firmer brake and notice when the front starts to push wide.'
    },

    {
      id: 'weight-transfer',
      title: 'Car physics: weight transfer',
      kicker: 'Chapter 5',
      minutes: 7,
      summary: 'Weight moves forward under braking, back under acceleration and sideways in corners, and that movement decides how much grip each tyre has at any moment.',
      sections: [
        {
          h: 'Braking pushes weight forward',
          p: [
            'When you brake, the car pitches forward and weight moves onto the front tyres. That gives the front more grip, which is why the car turns in more sharply just after braking. It also takes weight off the rear, which is why the back can feel light under hard braking.',
            'Brake firmly in a straight line, then ease off as you turn in. The weight shift helps the front bite while you are still slowing down.'
          ]
        },
        {
          h: 'Acceleration pushes weight back',
          p: [
            'Accelerating moves weight rearward. The rear tyres gain grip and the front gets lighter. A car with power at the rear can use that to pull out of a corner, but too much throttle too early will overwhelm the rear grip and the back steps out.',
            'Build the throttle as the car straightens and the weight settles back. Patience on the throttle is what turns a slow exit into a fast one.'
          ]
        },
        {
          h: 'Cornering shifts weight outward',
          p: [
            'In a corner, weight moves to the outside tyres. The outside tyres work hardest, and the inside tyres do less. That is why the outside tyres wear first and why a car can lose its inside front grip if you ask too much on turn-in.',
            'Smooth transitions are the key. Move from braking to turning to accelerating in a steady sequence. Snapping between them unloads one end, then the other, and the car feels unpredictable.'
          ]
        }
      ],
      tips: [
        'Brake in a straight line where you can. The more you brake while turning, the less grip you have for each.',
        'Get on the throttle as the car straightens. Early throttle upsets the rear.',
        'Feel the car settle after each input. A settled car is a predictable car.',
        'Smooth is fast. A big jerky input almost always costs time.'
      ],
      try: 'Do one lap focusing only on the transitions: brake, ease off as you turn, and build throttle as the car straightens.'
    },

    {
      id: 'drivetrains-and-handling',
      title: 'Car physics: drivetrains and handling',
      kicker: 'Chapter 6',
      minutes: 9,
      summary: 'The drive layout decides which axle loses grip first, and understeer and oversteer are the two ways a car tells you it has run out of grip.',
      sections: [
        {
          h: 'Drive layouts: FF, FR, MR, RR and 4WD',
          p: [
            'FF means front-engine, front-wheel drive. Power goes to the front, so the car tends to push wide under power. FR, front-engine rear-wheel drive, sends power to the back and is a common classic layout. MR is mid-engine, rear-wheel drive, which puts the mass in the middle and usually gives a balanced but unforgiving car. RR is rear-engine, rear-wheel drive, which is the rear-heavy layout that can snap around. 4WD sends power to all four wheels and is generally the easiest to put down power with, although it still has limits.',
            'You do not need to memorise the characteristics. Drive one of each and notice what the car does when you ask it to turn and accelerate at the same time.'
          ]
        },
        {
          h: 'Understeer: the car will not turn',
          p: [
            'Understeer means the front loses grip and the car goes straighter than you asked. You turn the wheel, but the car runs wide. It is the most common problem for beginners and usually comes from entering a corner too fast or turning in too hard.',
            'To fix it, slow down before the corner, ease off the steering a touch, and wait for the front to bite before you add throttle. In a front-wheel drive car, lifting off the throttle a little can help the front regain grip.'
          ]
        },
        {
          h: 'Oversteer: the back comes round',
          p: [
            'Oversteer means the rear loses grip and the back slides out. It is more dramatic and more dangerous, because a spin is quicker to develop than a push wide. It often comes from too much throttle mid-corner or from lifting off suddenly in a rear-heavy car.',
            'To fix it, ease off the throttle, look where you want to go, and make small steering corrections. In most cars, counter-steering means turning the wheel towards the direction of the slide. Keep the correction small. Big corrections make the slide worse.'
          ]
        }
      ],
      tips: [
        'Understeer is fixed by slowing down. Oversteer is fixed by easing off and steering gently.',
        'Learn your car’s balance on a track you know. Each car has a different tipping point.',
        'Use the throttle as a steering tool with rear-drive cars, but only once the car is settled.',
        'Assists can help with both problems while you learn. See Chapter 9.'
      ],
      try: 'Drive a lap of a familiar track and deliberately push the car to understeer in one corner, then fix it by lifting and turning gently. Repeat with oversteer on the next corner.'
    },

    {
      id: 'braking-and-the-line',
      title: 'Braking and the racing line',
      kicker: 'Chapter 7',
      minutes: 8,
      summary: 'The racing line is the path that keeps the most speed through a corner, and it is built from three points: where you brake, where you turn in, and where you exit.',
      sections: [
        {
          h: 'Braking points',
          p: [
            'A braking point is the spot where you start slowing for a corner. Brake too early and you lose time. Brake too late and you run wide or lock the tyres. The right point is the one that lets you reach the apex at the speed you want without running out of grip.',
            'Find braking points by repetition. Pick a marker, like a board or a kerb, and move your braking point closer to the corner in small steps until you find the limit.'
          ]
        },
        {
          h: 'Turn-in, apex and exit',
          p: [
            'Turn-in is where you start to steer into the corner. The apex is the innermost point of the corner, where the car is closest to the inside. The exit is where you point the car back towards the straight.',
            'A corner is a line, not a point. You enter wide, clip the apex, then exit wide. Only the apex is tight. Drivers who cut the apex too early run out of road on the exit and lose a lot of speed.'
          ]
        },
        {
          h: 'Slow in, fast out',
          p: [
            'The most useful principle in this chapter is simple. Slow in, fast out. Speed you carry into a corner is worth far less than speed you carry out of it, because the exit gives you the long straight that follows.',
            'If you are unsure whether to brake a little harder or accept a slightly slower entry, choose the slower entry. You will almost always be faster down the next straight.'
          ]
        }
      ],
      tips: [
        'Brake in a straight line, then trail the brake lightly into the apex to help the front turn in.',
        'Move your braking point closer in steps of a few metres. Do not jump straight to the limit.',
        'Look for the exit before the apex. Your exit decides your speed on the next straight.',
        'If you are running wide, you are probably braking too late or turning in too early.'
      ],
      try: 'Pick one slow corner on a track you know. Find a fixed marker for your braking point, then move it closer by a small step on each lap, stopping before you lock up.'
    },

    {
      id: 'licences-and-experiences',
      title: 'Licences and Circuit Experiences',
      kicker: 'Chapter 8',
      minutes: 7,
      summary: 'Licences test the core skills of braking, cornering and car control, and Circuit Experiences put those skills to work on real circuits with clear goals.',
      sections: [
        {
          h: 'Why do licences',
          p: [
            'The licence tests are the game’s way of checking your basic skills. They run in order from B to A, then International B and International A, and finally S. Each test asks you to drive a set course to a set standard, and each one builds on the one before.',
            'Licences are not optional if you want to enter the harder events. They also teach the habits that every later chapter depends on: smooth braking, a clean line and consistent lap times.'
          ]
        },
        {
          h: 'How to approach gold',
          p: [
            'Treat each licence test as a set of short lessons rather than a single lap. Learn the first corner, then the second, then join them up. Only then go for the time.',
            'Gold is the top award, and it is a good target because it asks for consistency as much as speed. Do not chase it on the first attempt. Go for a clean pass first, then work on the time once you know the course.'
          ]
        },
        {
          h: 'Circuit Experiences',
          p: [
            'Circuit Experiences are challenges set on real circuits, with specific goals and rewards. They are a good way to learn a track and a car without the pressure of a full race. Many are short, so they suit the habit of practising for a few minutes at a time.',
            'Use them to build your braking points, your racing line and your knowledge of how each car behaves. Experiences you have completed are also a good place to return to when you want to practise on a track you already know.'
          ]
        }
      ],
      tips: [
        'Do the licences in order. The tests build on each other.',
        'Get a clean pass before you chase a faster time.',
        'Use the same car for a whole licence block so you learn its behaviour.',
        'Revisit a Circuit Experience after a few days. You will see more than you did the first time.'
      ],
      try: 'Open the licence list, check which test is next, read its requirements, and drive one attempt for a clean pass without worrying about the time.'
    },

    {
      id: 'assists',
      title: 'Assists: what to use now, what to turn off later',
      kicker: 'Chapter 9',
      minutes: 7,
      summary: 'Assists keep the car from doing the wrong thing while you learn, and you should remove them one at a time as your confidence and skill grow.',
      sections: [
        {
          h: 'What each assist does',
          p: [
            'ABS, or anti-lock braking, stops the wheels locking under hard braking so the car keeps steering. TCS, traction control, cuts power when the rear wheels start to spin. ASM, active stability management, helps stop the car spinning by reducing power and applying braking on individual wheels. Countersteer assistance adds steering to help you catch a slide. The driving line shows you the racing line on the track. Braking assist, sometimes called auto-braking, helps you slow down at the right moment for a corner.',
            'These assists are not cheats. Professional drivers use the car’s own versions of many of them. They change how much you have to think about while you learn the car.'
          ]
        },
        {
          h: 'Use these now',
          p: [
            'Keep ABS on (Default). Most fast GT7 drivers never turn it off, and it lets you focus on the line and the corner. Keep TCS on while the car is new to you, especially in powerful rear-drive cars.',
            'Turn on the driving line while you learn a track. It shows you where to be and where the apex is. Keep countersteer assistance on until you can catch a slide without thinking about it.'
          ]
        },
        {
          h: 'Turn these off later',
          p: [
            'Turn off the driving line once you can find the racing line from memory on the tracks you run most often. Turn off braking assist once you can judge your braking points consistently. Turn off ASM and TCS last, when you can feel a slide developing and correct it before the car tells you.',
            'Change one assist at a time, and only when you can complete a few clean laps without it. Turning off everything at once is the usual way beginners end up in the barrier.'
          ]
        }
      ],
      tips: [
        'ABS stays on. Even top online drivers use it. The assists to remove are the driving line, braking assist, ASM and TCS.',
        'Change one assist at a time and drive a few laps before the next change.',
        'Take assists off in practice before you take them off in a race.',
        'If you turn an assist off and the car feels worse, turn it back on. There is no shame in it.'
      ],
      try: 'Take one lap of a familiar track with the driving line on and the rest of your assists as they are. Then take one lap with the driving line off and compare your braking points.'
    },

    {
      id: 'racing-others',
      title: 'Racing other cars: clean racing, penalties and Sport Mode',
      kicker: 'Chapter 10',
      minutes: 9,
      summary: 'Racing against AI teaches you the basics of passing and defending, and Sport Mode adds human opponents, a rating system and a reason to race cleanly every time.',
      sections: [
        {
          h: 'AI races first',
          p: [
            'AI opponents are the place to learn how to race other cars. They make mistakes, they hold lines, and they let you practise overtaking and defending without the stakes of a human race. Start with races where you finish in the top half and move up gradually.',
            'Pass on the straights and on the exits of corners where you have the grip and the momentum. Avoid passing on the inside of a corner you cannot make, because the car ahead will not give you room.'
          ]
        },
        {
          h: 'Clean racing and penalties',
          p: [
            'Clean racing means you do not cause contact, and you do not gain by pushing other drivers off the track. You are allowed to race hard. You are not allowed to make contact that could have been avoided. Leave space when you can, and when you are passed, let the car go.',
            'Penalties are given for causing contact, leaving the track to gain time, or breaking the rules of the event. A penalty can cost time or places, and in Sport Mode it affects your ratings. Learn the penalty rules for each event type so you know what is a foul before you commit to it.'
          ]
        },
        {
          h: 'Sport Mode: DR and SR',
          p: [
            'Sport Mode is the game’s online competitive mode. It uses two ratings. DR is your Driver Rating, which reflects your racing skill. SR is your Sportsmanship Rating, which reflects how cleanly you race. Both matter. A fast driver with a poor sportsmanship rating will not be matched in the best lobbies.',
            'Balance of Performance, often called BoP, is a set of adjustments that try to keep different cars competitive against each other in some events. Read the event details to see if BoP applies, because it changes which cars are worth taking.'
          ]
        }
      ],
      tips: [
        'Leave space. A little patience on the outside of a corner protects both cars.',
        'Do not chase a position you cannot hold. Finishing clean beats finishing first and getting penalised.',
        'Learn the penalty rules for each race before you enter it.',
        'Check the event details for BoP and tyre rules before you pick a car.'
      ],
      try: 'Enter one AI race in a car you know well. Finish it clean, and make one pass on a straight where you have a clear run.'
    }
  ],

  glossary: [
    { term: 'Apex', def: 'The innermost point of a corner, where the car is closest to the inside of the bend.' },
    { term: 'Contact patch', def: 'The small area of each tyre that touches the road and generates all of the grip.' },
    { term: 'Grip budget', def: 'The idea that each tyre has a fixed amount of grip to share between braking, turning and accelerating.' },
    { term: 'Understeer', def: 'When the front tyres lose grip and the car runs wider than you steered it.' },
    { term: 'Oversteer', def: 'When the rear tyres lose grip and the back of the car slides out.' },
    { term: 'Weight transfer', def: 'The movement of the car’s weight forward, back or sideways under braking, acceleration and cornering.' },
    { term: 'Trail braking', def: 'Easing off the brake gradually as you turn in, so the front keeps grip and the car rotates.' },
    { term: 'Racing line', def: 'The path through a corner or track that keeps the most speed.' },
    { term: 'Turn-in', def: 'The point where you begin to steer into a corner.' },
    { term: 'Slow in, fast out', def: 'The principle that a slightly slower entry to a corner usually gives a faster exit and a faster straight.' },
    { term: 'Braking point', def: 'The place where you start to slow down for a corner.' },
    { term: 'Drivetrain', def: 'The layout that decides which wheels the engine drives, such as front, rear or all four.' },
    { term: 'FF', def: 'Front-engine, front-wheel drive. Power goes to the front wheels.' },
    { term: 'FR', def: 'Front-engine, rear-wheel drive. Power goes to the rear wheels, with the engine at the front.' },
    { term: 'MR', def: 'Mid-engine, rear-wheel drive. The engine sits behind the driver and drives the rear wheels.' },
    { term: 'RR', def: 'Rear-engine, rear-wheel drive. The engine sits behind the rear axle and drives the rear wheels.' },
    { term: '4WD', def: 'Four-wheel drive. Power is sent to all four wheels.' },
    { term: 'Countersteer', def: 'Steering in the direction of a slide to bring the car back under control.' },
    { term: 'ABS', def: 'Anti-lock braking. Stops the wheels from locking under hard braking so you can keep steering.' },
    { term: 'TCS', def: 'Traction control. Reduces power when the driven wheels start to spin.' },
    { term: 'ASM', def: 'Active stability management. Helps stop the car spinning by managing power and braking.' },
    { term: 'Driving line', def: 'An assist that shows the racing line on the track so you can learn where to be.' },
    { term: 'Comfort, Sports, Racing tyres', def: 'The three dry tyre families in GT7, from least to most grip. Each comes in Hard, Medium and Soft.' },
    { term: 'Intermediate and wet tyres', def: 'Tyres designed for damp or wet tracks, where dry tyres lose grip quickly.' },
    { term: 'Café', def: 'The early-game hub where menu books guide you through your first tasks and rewards.' },
    { term: 'Menu books', def: 'Ordered sets of tasks in the Café that teach the basics and hand out early rewards.' },
    { term: 'Licence', def: 'A test of a driving skill, such as B, A, IB, IA or S, that unlocks harder events.' },
    { term: 'Circuit Experience', def: 'A challenge on a real circuit with a specific goal and reward, useful for learning tracks and cars.' },
    { term: 'World Circuits', def: 'The events held at the game’s circuits, with a range of race formats and rewards.' },
    { term: 'Brand Central', def: 'The new-car dealership in GT7, where you buy cars from manufacturers.' },
    { term: 'PP', def: 'Performance Points. A rating of a car’s overall performance, used to limit or match events.' },
    { term: 'BoP', def: 'Balance of Performance. Adjustments that keep different cars competitive against each other in some events.' },
    { term: 'Sport Mode', def: 'The competitive online mode that uses ratings to match drivers and reward clean racing.' },
    { term: 'DR', def: 'Driver Rating. A measure of your racing skill in Sport Mode.' },
    { term: 'SR', def: 'Sportsmanship Rating. A measure of how cleanly you race in Sport Mode.' }
  ],

  firstWeek: [
    { day: 'Day 1', do: 'Set up your wheel or controller. Set steering rotation and throttle and brake response, then drive one lap of a short track with no goal except smoothness.' },
    { day: 'Day 2', do: 'Work through the Café menu books in order. Complete the early tasks and collect the rewards without buying anything yet.' },
    { day: 'Day 3', do: 'Enter your first simple races. Finish each one clean, and learn the car you are given before you change anything about it.' },
    { day: 'Day 4', do: 'Practise braking. Pick one slow corner, move your braking point closer in small steps, and stop before you lock the tyres.' },
    { day: 'Day 5', do: 'Start the licence tests. Pass the first one cleanly, then drive the course again until your lines and braking feel repeatable.' },
    { day: 'Day 6', do: 'Try a Circuit Experience. Pick one that uses a car you already know, and focus on the racing line rather than the time.' },
    { day: 'Day 7', do: 'Review the week. Note which assists you still need, turn off one at a time for a few laps, and choose one car to keep learning next week.' }
  ]
};
