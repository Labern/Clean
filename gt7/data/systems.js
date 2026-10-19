// Race Systems: how GT7's race machinery works and how to use it. Drafted by a Haiku
// sub-agent, then fact-checked and sharpened (fuel map 1-6, TCS 0-5, ABS levels, the
// automatic pit limiter, MFD controls, assist names). Brake-balance direction is
// deliberately not asserted: the UI tells you to watch the on-screen indicator.

export const SYSTEMS = [
  {
    id: "pits",
    title: "Pit Stops",
    kicker: "Strategy",
    summary: "A pit stop lets you change tyres, refuel and repair damage during a race, at the cost of time in the pit lane. In longer races it is often the most important strategic call you make.",
    what: [
      "Pit stops happen in the pit lane, in your team's box. You enter at the marked entry, follow the lane to your box and stop there. Work is done while the car is stationary, and only the services you request are carried out. Asking for less work means less time stood still.",
      "Time lost comes from three places: the detour through the pit lane at the posted limit, the time stationary, and the time to rejoin the track. The total varies with the track and the services you take, so measure it yourself in practice on the track you are racing. Stationary time grows with each service you add, which makes a tyre-only stop usually the cheapest option if it does the job.",
      "An undercut is pitting before a rival so your fresh tyres gain time on their old ones while they are still out on track. An overcut is staying out longer, using clean air and your old tyres while the rival stops. Both depend on the gap, the difference in tyre condition and how much the stop costs on that track, so work the numbers before you commit."
    ],
    how: [
      "Check the race rules or lobby settings to see whether a stop is required, optional or not offered, and which services are available.",
      "Watch the fuel and tyre widgets on the HUD and the laps-remaining estimate. Plan a window a few laps before you actually need to stop, not at the last moment.",
      "Brake down to the pit-lane limit before the pit entry line. Once you cross it, GT7 holds you at the limit, so you only steer.",
      "Follow the pit lane to your box and stop in the marked spot. Hold the brake until the car is fully stationary, then release it.",
      "Open the pit menu while stopped. Select the tyres, fuel and repairs you want, then confirm. Wait for the service to finish before you move off.",
      "The limit lifts at the pit exit line. Stay on your side of the exit line and rejoin carefully: check your mirrors and the gap behind before you pull across."
    ],
    settings: [
      { name: "Pit stop rule", effect: "Whether a stop is required, optional or unavailable in that race. Check it before you start, because it decides your whole strategy." },
      { name: "Pit-lane speed limit", effect: "Applied for you between the pit entry and exit lines. Arrive at the entry line already slowed so you don't waste time braking into it." },
      { name: "Refuel amount", effect: "Refuelling time grows with the litres you add; a tyre change is a roughly fixed cost. Add only the fuel you need to finish plus a small margin." }
    ],
    tips: [
      "Pit early enough to rejoin in clean air, or pit when the rivals who stopped before you are losing the most time.",
      "Practise the pit entry, the box stop and the exit on a free run before a race, so the limiter and the stop become routine.",
      "Take only the services that change your race. Every extra task adds stationary time.",
      "Check the gap to the car behind before you exit. Rejoining into traffic can cost more than the stop itself."
    ],
    mistakes: [
      "Arriving at the pit entry line too fast and braking hard into it, which costs more time than a smooth approach.",
      "Stopping in the wrong place, which costs time while you sort the car out.",
      "Pitting without checking the fuel and tyre numbers first, so you stop for less than you needed.",
      "Releasing the brake before the car is fully stationary.",
      "Brimming the tank when you only need a few laps of fuel. Every extra litre is time stood still and weight carried."
    ],
    wheel: "There's no limiter to map: GT7 applies the pit-lane limit itself. Map the MFD controls instead, so you can check the fuel pages and set the fuel map on the in-lap without taking your hands off the wheel. Assign these in GT7 under Options, then Controller settings.",
    related: ["fuel", "tyres", "penalties", "weather"]
  },
  {
    id: "fuel",
    title: "Fuel Management",
    kicker: "Strategy",
    summary: "Fuel is weight, and weight costs lap time. Whether you can finish without a stop, and how fast you are on the way, depends on how you manage the tank.",
    what: [
      "Fuel consumption in GT7 is controlled by a race setting. A higher consumption setting empties the tank faster, which means more stops or more careful driving. The same car can be a non-issue on one setting and a full strategy problem on another, so check the setting before every race.",
      "Fuel maps change how the engine delivers power for a given throttle input, trading power against consumption. A richer map gives more power and uses more fuel. A leaner map saves fuel and feels softer. GT7 numbers them 1 to 6: Map 1 is full power and full consumption, each step up trades a little power for lower consumption, and Map 6 is the leanest. You change it mid-race from the multi-function display (MFD), and the fuel gauge and laps-remaining estimate tell you whether you can afford a richer map.",
      "The fuel gauge shows what is left, and the laps-remaining estimate projects it from your recent pace. The estimate needs a few clean laps before it means much, so do not react to it straight away. Fuel weight also matters. A full tank makes the car heavier, which slows it in corners and under braking. The effect is real but small, and it fades as the tank empties."
    ],
    how: [
      "Before the race, check the event settings for the fuel consumption setting and whether refuelling is required, optional or unavailable.",
      "In practice, run several laps at race pace and watch how much fuel each one uses. Work out a per-lap figure at your normal pace.",
      "Compare the laps-remaining estimate with the laps left in the race. If you are short, plan a stop or change how you drive.",
      "Use a leaner fuel map on straights and sections where you do not need the power, and return to a richer map for overtaking or defending.",
      "If the race demands it, lift and coast early into slow corners and braking zones. Lift only as much as you need to make the fuel.",
      "Recheck the estimate every few laps, especially after a yellow flag, a restart or a change in pace."
    ],
    settings: [
      { name: "Fuel consumption setting", effect: "Scales how fast the tank empties. Higher means you need to save more, or stop more often." },
      { name: "Fuel map 1-6", effect: "Map 1 = full power, highest consumption. Higher numbers save fuel and cost power. One of the few things you can still change in BoP races." }
    ],
    tips: [
      "Measure fuel use on a race-length run in practice, not on one fast lap.",
      "Do not start saving fuel in the first lap or two. The estimate is still settling, and early over-saving costs places.",
      "If the race allows it, run the richer map from the start and only save when the numbers tell you that you have to.",
      "Treat lift and coast as a tool for when fuel forces the choice, not as a default for every corner."
    ],
    mistakes: [
      "Leaving the richer fuel map on for the whole race, then running short on the final laps.",
      "Trusting the laps-remaining estimate after one lap or straight after a yellow flag.",
      "Lifting too early in every corner. This loses more time than it saves in most races.",
      "Forgetting the car is heavier at the start, so it handles differently in the early laps.",
      "Not checking the consumption setting before a long race, so you plan for the wrong numbers."
    ],
    wheel: "On a G PRO, map the fuel map control to a d-pad direction or button you can reach without taking your hands off the wheel. If GT7 lets you assign it to one of the wheel's rotary controls, that gives you a quick nudge up or down. Keep it away from the shift paddles. Assign these under Options, then Controller settings.",
    related: ["pits", "tyres", "hud"]
  },
  {
    id: "tyres",
    title: "Tyres and Compounds",
    kicker: "Grip",
    summary: "Tyres decide grip, and grip decides almost everything else. Choosing the right compound for the surface and managing wear over a stint is the difference between a clean run and a slide into the barrier.",
    what: [
      "GT7 offers three tyre families: Comfort, Sports and Racing. Within each family you choose hard, medium or soft. Harder compounds last longer and give less grip. Softer compounds grip more, warm up faster and wear faster. Comfort is the most durable and least grippy family, Racing the most grippy and the fastest to wear, and Sports sits between them. Intermediate and Heavy Wet tyres are for wet conditions, and only make sense while the track is wet or drying.",
      "Wear is shown on the HUD through the tyre widget. Tyre wear settings in the race rules change how quickly the tyres degrade. A high wear setting can turn a one-stop race into a multi-stop race. Some events require a specific compound or a minimum number of tyre changes, so read the rules before you choose.",
      "Warm-up matters. Cold tyres grip less, so the first lap or two after a stop or restart can feel loose. Scrub the tyres in gently under braking and through the first few corners before you push. As the tyres wear, grip falls away gradually, and the car starts to push on entry or slide on exit late in a stint."
    ],
    how: [
      "Read the race rules for required compounds, a minimum number of tyre changes, and the tyre wear setting.",
      "In practice, run several laps on each compound you are considering, and note how the lap time drops as the tyre wears.",
      "Choose the softest compound that will still last the race distance with some margin, or the compound the rules require.",
      "Watch the tyre widget on the HUD during the race. Plan the stop for when wear is starting to cost you lap time, not when the car is already sliding.",
      "On cold tyres, avoid big steering and throttle inputs in the first corners until the grip builds.",
      "In the wet, switch to Intermediate or Heavy Wet tyres once conditions justify it, and switch back to slicks when the track has dried."
    ],
    settings: [
      { name: "Tyre wear setting", effect: "Scales how fast tyres degrade. Higher wear means more stops and more careful use of the compound." },
      { name: "Required compound or tyre change rules", effect: "Set by the event. Breaking them can bring a penalty, so check them before you pick a tyre." }
    ],
    tips: [
      "Run a long stint in practice. One fast lap on fresh tyres tells you very little about lap 20.",
      "Watch the drop-off in lap time, not the absolute figure. The drop-off tells you when the stop is due.",
      "Choose the compound for the race distance and the track's abrasiveness, not just for the fastest qualifying lap.",
      "On cold tyres, expect the car to feel loose for a short time. Grip comes in gradually, so do not chase it."
    ],
    mistakes: [
      "Choosing a soft compound for a long race because it was fastest in qualifying, then falling away in the second half.",
      "Pushing hard on cold tyres straight after a stop or restart, and sliding off.",
      "Ignoring a required compound rule and collecting a penalty you could have avoided.",
      "Staying on intermediates or wets after the track has dried, which costs a lot of lap time.",
      "Overworking the tyres in traffic, which speeds up wear for no real gain."
    ],
    wheel: "On a wheel, you feel tyre wear through the car getting loose or pushing late in the stint. Set your force feedback so you can feel grip changing at the front and rear. Keep the tyre-related menu off a button you could hit by accident. Use the d-pad for menu navigation only, and keep your hands on the wheel through the corners.",
    related: ["pits", "fuel", "weather", "brake-balance"]
  },
  {
    id: "tcs",
    title: "Traction Control",
    kicker: "Assists",
    summary: "Traction control stops the driven wheels spinning under power. Set it too low and the car steps out on corner exit. Set it too high and it cuts your throttle when you need it most.",
    what: [
      "TCS intervenes when it detects wheelspin, reducing power or applying control to the driven wheels. You choose a level in the driving assists, and higher levels intervene more and sooner. The level is a trade-off between grip and speed. A low level lets the car spin more and keeps more speed, while a high level holds the car straight but can make it feel like it is fighting you.",
      "GT7's TCS runs from 0 (off) to 5 (most intervention). You can change it mid-race from the MFD, which is how fast drivers handle a drying track or tyres that are going off. Beyond the Apex suggests learning on a middle setting and stepping down as your throttle foot improves, because a tyre makes its best grip with a little slip.",
      "TCS does not replace good throttle control. It catches the worst of the wheelspin. Good drivers modulate the throttle so TCS rarely needs to act, and then lower the level or switch it off once they are confident in the car."
    ],
    how: [
      "Open the driving assists before the race and set TCS to a level you can test over several laps.",
      "Run a session at the default level, and watch where the car intervenes on corner exit, such as a visible power cut or a reduction in wheelspin.",
      "Lower the level one step at a time. Keep the level where the car stays straight with only small corrections.",
      "When you are comfortable, reduce or switch off TCS for qualifying, and watch for wheelspin on exit.",
      "In the race, change TCS only when conditions change, such as rain arriving or the track drying, and only if you have a quick way to change it.",
      "Recheck the setting before each session, so a race does not start with a level you did not intend."
    ],
    settings: [
      { name: "0", effect: "Off. All the traction is your right foot." },
      { name: "1-2", effect: "Light. Catches big mistakes, lets the tyre slip enough to make peak grip. Where most quick drivers live in the dry." },
      { name: "3", effect: "The learning setting. Safe on exits, costs a little drive." },
      { name: "4-5", effect: "Heavy. Wet tracks, worn tyres, or a powerful rear-drive car you don't know yet." }
    ],
    tips: [
      "Work with the throttle, not against it. Smooth inputs keep TCS quiet and the car predictable.",
      "Use a higher level in the wet and on worn tyres, and bring it down as grip returns.",
      "Reduce TCS in small steps. Big jumps leave you with a car that snaps on exit.",
      "Test each level over a full lap, since a level that feels fine on one corner can be wrong on another."
    ],
    mistakes: [
      "Running a high TCS level because you think it makes you faster. It often costs time on exit.",
      "Stabbing the throttle to make the car step out, then having TCS cut in and unsettle it.",
      "Forgetting to change TCS when conditions change, such as rain starting or the track drying.",
      "Judging the level from one corner and then being surprised by the next."
    ],
    wheel: "On a wheel, you feel traction loss through the force feedback and the steering. Modulate the throttle pedal in small amounts. If you change assists with a button or d-pad direction, map it where you can reach it without lifting your hands. Keep your pedal settings sensible, since a pedal that is too sensitive makes TCS work harder.",
    related: ["asm", "abs", "tyres", "weather"]
  },
  {
    id: "abs",
    title: "ABS",
    kicker: "Assists",
    summary: "ABS stops the wheels locking under braking, so you can keep steering. It is one of the most useful assists when you are learning, and one that many experienced drivers turn down or off to brake later and harder.",
    what: [
      "ABS adjusts brake pressure at each wheel to stop it locking. With ABS on, you can brake hard and still steer. Without it, a locked wheel gives you a flat spot on the tyre and a car that will not turn.",
      "GT7 offers three ABS settings: Off, Weak and Default. Off gives no help, Weak intervenes later and less, Default intervenes the most. Pick the setting you can brake confidently with, then see whether you can brake later with a little less help.",
      "ABS and ASM are linked in GT7. ASM is off when ABS is off, so turning ABS off also removes ASM. The car is then less supported overall. Check the assist menu after changing ABS, since the other assists may change with it."
    ],
    how: [
      "Open the driving assists before racing and set ABS to a level you can test.",
      "Run a few laps braking into a heavy braking zone, and note whether the car stays straight and steerable.",
      "When you feel comfortable, move to a weaker setting or off. Practise in a safe run first, not in traffic.",
      "Check the ASM setting after changing ABS, since ASM is off when ABS is off.",
      "Build up to the setting you intend to race with, then recheck it before the race."
    ],
    settings: [
      { name: "Off", effect: "No ABS. You must brake with more care, and ASM is also off. Best for experienced drivers who want to brake later." },
      { name: "Weak", effect: "Intervenes later and less. A middle ground: more feel, still protected from a full lock." },
      { name: "Default", effect: "Intervenes the most. Easiest to drive and what Beyond the Apex recommends while learning." }
    ],
    tips: [
      "Learn to brake with ABS on before you turn it off. The technique is different without it.",
      "Use the feel of the pedal and the wheel to learn what a lock-up feels like, so you catch it early.",
      "If you turn ABS off, brake in a straight line first, then ease off as you turn in.",
      "Brake to the same markers on each lap. This makes it easier to notice when the car is locking."
    ],
    mistakes: [
      "Turning ABS off and braking as hard as you did with it on. This locks the front tyres and sends you wide.",
      "Stamping on the brake in the wet with ABS off, which causes lock-ups at the worst moment.",
      "Forgetting that ASM is off too, and expecting the car to recover on its own.",
      "Keeping ABS at the strongest setting when you actually want the car to rotate more on turn-in."
    ],
    wheel: "On a G PRO, learn the pedal feel of ABS working, and try to brake in a consistent way rather than stabbing. If your pedals work by pressure, learn to brake with pressure rather than travel. Keep any assist-change control away from the brake area. Assign it under Options, then Controller settings.",
    related: ["asm", "tcs", "brake-balance"]
  },
  {
    id: "asm",
    title: "ASM and Countersteering Assist",
    kicker: "Assists",
    summary: "Active Stability Management (ASM) and countersteering assist help you recover when the car starts to slide. They are useful when learning, and a common thing to turn off once you are fast.",
    what: [
      "ASM reduces the chance of a spin by applying control to individual wheels when the car starts to rotate more than you intend. It works alongside TCS and ABS. It acts mainly when the car is close to losing control, so it rarely feels like a constant hand on the wheel.",
      "Countersteering assist adds steering in the direction needed to catch a slide. Like ASM, it helps you recover. It can also feel like the car is pulling you back, which makes it harder to learn where the car's true limit is.",
      "Fast drivers often turn them off, or turn them down, for three reasons. They can conflict with precise inputs, they can make the car feel less responsive, and they hide how the car really behaves at the limit. Without them, you rely on throttle and steering, and you learn to control oversteer rather than avoid it. Turning them off also makes you a better judge of grip, which is what actually makes you quicker."
    ],
    how: [
      "Open the driving assists before racing and find the ASM and countersteering options.",
      "Start with both on for a few laps, so you can see how the car reacts when you overdrive a corner.",
      "Turn countersteering off first and test on a dry, open section of track, so you learn the car's natural behaviour.",
      "Turn ASM down or off once you can control slides with the throttle and steering.",
      "Keep ASM on for unfamiliar cars or wet races, where a spin costs much more.",
      "Recheck the setting before each race, and again after any change to ABS."
    ],
    settings: [
      { name: "ASM", effect: "Helps prevent spins by intervening when the car rotates too far. Strongest protection, and the most intrusive, when it is on." },
      { name: "Countersteering assist", effect: "Adds steering to catch slides. Helpful when learning, but it can mask the car's real behaviour." }
    ],
    tips: [
      "Treat ASM as a safety net, not a crutch. Learn to catch slides first.",
      "In the wet, keep ASM on until you know the car's limits in the rain.",
      "Switch assists off one at a time, so you can tell which one was doing the work.",
      "Turning ASM off does not make the car faster on its own. Your driving does."
    ],
    mistakes: [
      "Turning every assist off on day one and spinning in every corner.",
      "Relying on ASM to save a bad lock-up or an over-ambitious corner entry, then being surprised when it does not.",
      "Leaving countersteering on to try to be fast, then fighting it on corner exit.",
      "Changing assists without testing the car afterwards, so you do not know what has changed."
    ],
    wheel: "With ASM and countersteering off, force feedback is your main source of information about grip. On a G PRO, set force feedback so you can feel the front and rear grip change. Keep the assist toggle away from the shift paddles, so you do not press it mid-corner. Assign it under Options, then Controller settings.",
    related: ["tcs", "abs", "brake-balance"]
  },
  {
    id: "brake-balance",
    title: "Brake Balance",
    kicker: "Setup",
    summary: "Brake balance sets how the braking force is shared between the front and rear wheels. It is one of the quickest ways to change how the car turns under braking, and one of the most useful adjustments to make during a race.",
    what: [
      "GT7's brake balance runs from -5 to +5 with 0 as the car's standard split. One end puts more braking on the front wheels, the other more on the rear; watch the front/rear indicator on screen as you change it so you know which way you've moved. The total braking force stays about the same: you are changing the split, not the strength. It's one of the few settings you can still change in BoP races, and you can adjust it mid-race from the MFD.",
      "Too far forward, the front wheels lock first, the car runs wide and feels stable but slow to turn in. Too far rearward, the rear can lock and the car becomes unstable under braking, with a tendency to rotate or snap when you brake hard. Good settings sit between the two, where the car stays stable under heavy braking and rotates well on turn-in.",
      "Adjust the balance during a race when tyres wear, when the track changes between wet and dry, or when the fuel load changes. A heavier car brakes differently, and tyre wear changes the grip at each axle, so a setting that worked at the start may not suit lap 30."
    ],
    how: [
      "Set the balance in practice before the race. Make small changes, one step at a time, and drive several laps after each one.",
      "Watch for lock-ups and instability. Front lock-ups point to too much front braking, and rear instability points to too much rear braking.",
      "Find the setting where the car stays stable under heavy braking and turns in well.",
      "Adjust the balance during the race using the control you have mapped, in small steps.",
      "Recheck the balance after a pit stop, a tyre change or a change in the weather."
    ],
    settings: [
      { name: "Front bias", effect: "More braking on the front. Helps stability under braking, but can cause front lock-ups and make the car run wide." },
      { name: "Rear bias", effect: "More braking on the rear. Helps the car rotate on turn-in, but can make it unstable or cause rear lock-ups under hard braking." }
    ],
    tips: [
      "Make one change at a time, and drive a few laps before you make another.",
      "If the car is unstable under braking, move towards the front. If it will not rotate on turn-in, move towards the rear.",
      "If the front starts to lock late in a stint, move the balance a step towards the rear to take some braking off the front.",
      "Use the balance to fix the car, not to hide a braking mistake."
    ],
    mistakes: [
      "Making a large jump in balance and then wondering why the car has got worse.",
      "Mistaking a lock-up caused by too much braking pressure for a balance problem, then changing the wrong thing.",
      "Setting the balance for a dry track and forgetting to change it when the rain starts.",
      "Ignoring the effect of tyre wear on the way the car brakes."
    ],
    wheel: "On a G PRO with a d-pad, brake balance is a quick change if you map it to a d-pad direction. You can nudge it without taking a hand off the wheel. Keep brake balance off the shift paddles. Assign it under Options, then Controller settings.",
    related: ["abs", "asm", "tyres", "mfd"]
  },
  {
    id: "mfd",
    title: "The MFD and Quick Menu",
    kicker: "Controls",
    summary: "The multi-function display (MFD) is the quick menu you use to read information and change some settings while driving. Knowing what you can change on the track, and how to reach it on a controller or a wheel, saves you fumbling mid-race.",
    what: [
      "The MFD in GT7 is a strip of pages you scroll through while driving. On a controller, left/right on the d-pad moves between items and up/down changes the selected value. Pages include the fuel map, brake balance and TCS, plus information like fuel remaining, tyre condition, lap times and, in variable-weather races, the weather radar. Which pages appear depends on the event and the car.",
      "Only a short list of settings can be changed on track, typically those that do not need a stop. Settings that require a pit stop, such as tyre choice, are not available until you are in the pits. The list changes between races and cars, so check the in-game options rather than relying on memory.",
      "On a controller, the menu is usually navigated with the d-pad and face buttons. On a wheel, you reach the same menu through the buttons you have mapped, so your mapping decides how quickly you can use it. Set up your mapping before you race, so you are not searching for buttons mid-session."
    ],
    how: [
      "Before the race, open the controller settings and find the button for the quick menu or MFD. Note which button your device uses.",
      "In practice, open the menu and scroll through each page to see what it shows and what you can change.",
      "Map the controls you use most, such as brake balance, TCS, the fuel map and the pit limiter where it is available, to buttons you can reach without leaving the wheel.",
      "Practise opening the menu, changing one setting and closing it, while driving a slow lap in a safe section.",
      "Use the menu on straights or in safe sections. Avoid changing settings under braking."
    ],
    settings: [],
    tips: [
      "Keep a note of your mapped buttons on a card or on your phone, next to the wheel.",
      "Agree on a small set of changes you expect to make mid-race, then practise those only.",
      "Check the value on screen before you commit, especially for brake balance where the number matters.",
      "Use the pages for information as well, such as fuel and tyre numbers, so you do not have to look elsewhere."
    ],
    mistakes: [
      "Opening the menu under heavy braking and running wide.",
      "Assuming a setting can be changed on track when it only works in the pits.",
      "Trying to set up buttons in the middle of a race.",
      "Changing several settings at once, so you cannot tell which change helped."
    ],
    wheel: "On a G PRO, the d-pad is the most natural way to move through the MFD pages. Map the menu open button to a button you can find by feel, and keep it clear of the paddles and any button you use for shifting or lights. Assign these under Options, then Controller settings.",
    related: ["brake-balance", "tcs", "fuel", "hud"]
  },
  {
    id: "weather",
    title: "Weather and Wet Racing",
    kicker: "Conditions",
    summary: "Rain changes the grip of every corner, and it does so unevenly. Reading the weather radar, the track wetness and the dry line lets you choose the right tyres and lines to keep you on the track.",
    what: [
      "Weather in GT7 can change during a race. The weather radar shows where rain is heading, so you can see when it is likely to reach you. Use it to plan tyres, and to decide whether to pit before the track gets wet, rather than reacting once you are already sliding.",
      "Track wetness builds up in patches. The racing line usually dries first and is the grippiest part of the track, while the rest can still be wet. The dry line is the strip that dries as cars run on it. It is often narrow and can be slippery, even when the rest of the track still looks wet.",
      "Tyre choice follows the conditions. Intermediate tyres work in light rain and on drying tracks. Heavy Wet tyres are for heavier rain. Slicks on a wet track are slow and risky, but switching back to slicks is worth it once the dry line is clearly usable and lap times on slicks beat those on wets."
    ],
    how: [
      "Check the forecast and the weather radar before the race, and note when rain is expected.",
      "Watch the track wetness and the dry line as you drive. Look for the sheen on the surface and feel how the car responds in each corner.",
      "Decide on intermediates or wets when the rain is heavier than slicks can cope with, and pit for them before the track is too far gone.",
      "Pit for slicks when the dry line is clear and your lap times on slicks are faster than on wets.",
      "Adjust TCS, ASM and brake balance when conditions change, since grip falls quickly in the wet.",
      "Recheck the radar every lap or two in a changing race."
    ],
    settings: [
      { name: "Weather conditions", effect: "Set by the event, and can change during a race. Plan for changes rather than assuming a constant track." }
    ],
    tips: [
      "Do not drive off the wet line into the standing water unless you have to. Stay on the line you trust.",
      "Track the dry line, not the whole track. It is often a narrow strip, and it is the fastest place to be.",
      "Do not wait for the whole track to dry before switching back to slicks. A usable dry line is enough to start.",
      "Brake earlier and more smoothly in the wet, and use TCS and ABS to protect the tyres and your line."
    ],
    mistakes: [
      "Staying on slicks too long, or pitting for wets too late.",
      "Following the dry line without watching the wet patches beside it, and sliding off.",
      "Ignoring the radar and getting caught out by a sudden shower.",
      "Pitting for the wrong tyre and losing a lot of time over the rest of the stint."
    ],
    wheel: "In the wet, the wheel is your main grip sensor. Keep force feedback strong enough that you feel the front lose grip before it goes. Use the d-pad to adjust assists quickly as conditions change, and keep it away from the paddles. Assign these under Options, then Controller settings.",
    related: ["tyres", "pits", "tcs", "asm"]
  },
  {
    id: "starts",
    title: "Race Starts",
    kicker: "Racecraft",
    summary: "The start decides the first corner and often the first lap. Standing and rolling starts are different, and a bad launch or a careless first corner can cost you several places in seconds.",
    what: [
      "A standing start begins from stationary on the grid, with the countdown or lights deciding when you go. The launch needs smooth throttle, and a controlled clutch if you drive a manual. TCS helps keep the wheels from spinning. A rolling start begins while the field is moving behind a lead car. Timing and spacing matter more than the launch itself, because you are already moving.",
      "Most places lost in a race are lost in the first corners. Cars are close together and braking late, and contact is common. Keep the car straight in the first few seconds, leave the car ahead room, and watch the cars on either side before you turn in.",
      "First-lap etiquette is about being predictable. Do not dive into a braking zone with a car alongside unless there is clear room. Give cars you have passed space, and avoid causing a chain reaction, which can end your race and others' races too."
    ],
    how: [
      "Check the event settings to see whether the race uses a standing or rolling start.",
      "In a free session, practise standing starts on the grid. Launch with smooth, controlled throttle, aiming for a quick start without wheelspin.",
      "For a rolling start, hold your place in the queue, keep a steady gap to the car ahead, and load the throttle smoothly.",
      "Keep the car straight in the opening seconds, then look for the gap into the first corner.",
      "Brake for the first corner with room to spare, since the cars around you will be braking late.",
      "Once through the first corner, settle into your race pace and stop checking the mirrors every second."
    ],
    settings: [],
    tips: [
      "Build a start routine, and use the same throttle and clutch inputs every time.",
      "Watch the brake lights of the car in front and the car alongside, not only the start lights.",
      "Do not lunge at the first corner. Most places are lost in the first braking zone, not at the start.",
      "Practise your starts on the same grid layout you will race from."
    ],
    mistakes: [
      "Spinning the wheels on launch by using too much throttle, which can also bring TCS in.",
      "Moving before the start signal, which can be penalised.",
      "Turning into the car alongside on the first corner.",
      "Braking too late because you think you can out-brake everyone.",
      "Ignoring the car behind, so you brake suddenly into a queue."
    ],
    wheel: "On a G PRO, keep both hands on the wheel and modulate the throttle pedal smoothly. If you drive a manual, practise the clutch on the pedal until it is consistent. Use the d-pad for menus only, not during the start. Assign any other controls under Options, then Controller settings.",
    related: ["tcs", "penalties", "asm"]
  },
  {
    id: "penalties",
    title: "Penalties",
    kicker: "Racecraft",
    summary: "Penalties can turn a good race into a bad one. Track limits, shortcuts and collisions can all cost you, and in Sport Mode, they also affect your Sportsmanship Rating (SR), which shapes the races you are matched into.",
    what: [
      "Track-limit penalties apply when you go beyond the track boundaries, particularly if you gain an advantage by doing so. Shortcut penalties apply when you cut a corner or use an unmarked route. Collision penalties depend on the contact, and the rules decide who is at fault. The rules for each event set how strictly these are enforced, so read them before you race.",
      "Time penalties are served by slowing down as the game asks. The game shows a message with the penalty type and what to do. Follow the instructions exactly and complete the penalty before the race ends. The precise way a penalty is served can vary by event, so check the message each time.",
      "In Sport Mode, your SR is affected by penalties and by how you drive. A clean race helps your rating over time, and poor driving lowers it. SR is separate from your race position, but it matters because it affects which lobbies and races you can join. Protect it as you would your results."
    ],
    how: [
      "Read the event rules before you race, including the track-limit, shortcut and penalty rules.",
      "In practice, find the track-limit markings and kerbs, and note where the line is judged to be out.",
      "If a penalty is given, read the message carefully, and note what type it is and how to serve it.",
      "Serve a time penalty as soon as the game shows the requirement, and follow the speed or area instructions.",
      "In Sport Mode, avoid contact and drive cleanly to protect your SR.",
      "After the race, review any penalty messages you received, and adjust your approach for the next race."
    ],
    settings: [
      { name: "Sport Mode and SR", effect: "Penalties and driving conduct affect your Sportsmanship Rating, which affects matchmaking. Clean racing protects it." }
    ],
    tips: [
      "Keep one or two wheels inside the lines on exits. Cutting a little loses more than it gains.",
      "Avoid contact. In Sport Mode, your SR matters more over time than any single race.",
      "If you get a penalty, serve it and move on. Arguing with it costs you the next corner too.",
      "Learn the track limits on each track, since kerbs and lines differ from one circuit to another."
    ],
    mistakes: [
      "Riding the kerbs repeatedly and collecting a penalty you did not expect.",
      "Ignoring a penalty message and finishing without serving it.",
      "Serving a penalty too fast or too slow, and picking up a second penalty.",
      "Making contact in a battle and assuming it is fine because it looked small."
    ],
    wheel: "On a wheel, track limits are easier to judge through the kerb and surface feedback in the force feedback. Set force feedback so you feel the kerbs clearly. Keep penalty-related menus off the paddles. Assign these under Options, then Controller settings.",
    related: ["starts", "asm", "damage", "hud"]
  },
  {
    id: "bop",
    title: "Balance of Performance",
    kicker: "Rules",
    summary: "Balance of Performance (BoP) adjusts cars so that different models are closer on pace. You cannot change BoP itself, but you still control your tuning, tyres, fuel and driving, and those decide where you finish within the balance.",
    what: [
      "BoP is a set of adjustments applied to cars, usually in competitive events, to bring them closer together on performance. It can change power, weight or other values for a particular car model. The game applies it, so you do not choose it. Check it before you race, because the car you expect may not behave as you remember.",
      "BoP sets the performance ceiling for each car, but the rest is yours. Tuning that is allowed, tyre choice, fuel strategy, brake balance and assists all change the result. Two drivers in the same BoP car can finish very differently.",
      "Each event sets its own rules. Some restrict tuning, some require stock parts, and some change the BoP from event to event. Read the rules before you buy or upgrade a car, so you do not find that your setup is not allowed."
    ],
    how: [
      "Read the event rules before you enter, and look for any note that the event uses BoP.",
      "Check the car's stats and any restriction shown in the car selection or the event listing.",
      "Compare your car's pace in practice against other cars on the same track, rather than relying on your memory of the car.",
      "Set up the allowed tuning and tyres for the track, within the event's rules.",
      "Put your effort into strategy, tyres and driving, which BoP does not cover."
    ],
    settings: [],
    tips: [
      "Do not assume your favourite car is slow or fast. Test it under BoP before you judge it.",
      "If a car looks off on one track, test it on another before you draw a conclusion.",
      "Use the allowed tuning options to suit your track and your tyres.",
      "Expect BoP to change between events, and read each event's rules rather than assuming the last one."
    ],
    mistakes: [
      "Buying or upgrading a car for an event without checking the rules, then finding it is restricted.",
      "Assuming BoP removes all the differences. It narrows the gaps but does not remove driver error.",
      "Judging a car on one lap and ignoring tyre wear and fuel.",
      "Trying to tune around a rule that the event enforces."
    ],
    wheel: "Your wheel does not change BoP, but the controls you use during a race do. Map brake balance, TCS and the quick menu to your G PRO, so you can use the adjustments you are allowed without taking your hands off the wheel. Assign these under Options, then Controller settings.",
    related: ["tyres", "fuel", "penalties"]
  },
  {
    id: "damage",
    title: "Damage",
    kicker: "Rules",
    summary: "The damage setting decides how much a contact hurts the car. Light damage lets you keep racing after small bumps. Heavy damage makes every contact count. Know which one is on before you go for a gap.",
    what: [
      "Damage affects the car's performance after impacts, which can change its handling and power. The damage setting controls how much a contact changes the car. Light damage affects the car less. Heavy damage makes contact more costly, which changes how you race wheel to wheel.",
      "Damage is not the same as cosmetic marks. In a race, the difference that matters is the performance effect, which can cost you lap time in later corners and in the straights. Repeated contact adds up, even when each hit seems small.",
      "The impact matters as well as the setting. A heavy hit at speed does more harm than a gentle touch. Check the damage setting in the event rules before each race, since it changes how you should approach every battle."
    ],
    how: [
      "Check the damage setting in the event or race settings before you start.",
      "In practice, run a few laps with the setting you will race on, and note how contacts change the car.",
      "If damage is heavy, plan your overtakes to avoid contact, and leave more room on corner entries.",
      "If damage is light, you can race a little harder, but still avoid repeated contact.",
      "After any contact, check how the car handles in the next corner before you decide how hard to push."
    ],
    settings: [
      { name: "None", effect: "Contact costs no performance. Common in casual lobbies; it does not make contact acceptable." },
      { name: "Light damage", effect: "Contact affects the car less. You can race closer, but repeated hits still add up." },
      { name: "Heavy damage", effect: "Contact costs much more. Clean passes and careful entries matter far more." }
    ],
    tips: [
      "On heavy damage, treat every wheel-to-wheel moment as a risk. Go for clean passes.",
      "Keep an eye on the car after a contact. Small losses can grow over a stint.",
      "Practise racing close to other cars in a lobby with the same damage setting.",
      "On light damage, you can be more assertive, but do not rely on it."
    ],
    mistakes: [
      "Racing with heavy damage as if it were light, and suffering in the next corners.",
      "Making contact early to pass a rival, then losing more time than the pass gained.",
      "Ignoring a change in handling after a light hit and pushing into the next braking zone.",
      "Not checking the damage setting before a race, and assuming it is the same as last time."
    ],
    wheel: "A wheel gives you the best feel for damage, because the steering changes after a hit. Keep force feedback high enough to feel the change, but not so high that it hides the other signals you need. Keep any menu button away from the paddles. Assign these under Options, then Controller settings.",
    related: ["penalties", "starts", "hud"]
  },
  {
    id: "ghost-assists",
    title: "Racing Line and Braking Guides",
    kicker: "Learning",
    summary: "The racing line, braking markers, ghost laps and auto-drive help you learn a track. Used well they speed up learning. Used at the wrong time, or left on in races, they replace your own feel for the car.",
    what: [
      "GT7's learning aids are the Driving Line (the racing line drawn on the road), the Braking Area (where to brake), the Braking Indicator (how hard), Suggested Gear, and two that take inputs off you: Auto-brake and Auto-Drive. They are guides, not targets, and most useful on a new track or car. All of them live in the driving assist settings.",
      "A ghost, or reference lap, shows a benchmark lap alongside yours, so you can see where time is gained or lost. It is a comparison, not a set of instructions. Use it to find where you lose time, not to copy every input.",
      "Auto-drive, where the car drives itself, is a learning tool. It shows a line, braking and throttle points. It is designed to be consistent, not to be fast, so it does not represent race performance. Turn it off before you race, and do not judge your own lap times while it is on."
    ],
    how: [
      "Open the driving aids before practice, and turn on the racing line and braking markers if they are available.",
      "Drive a few laps with the line on, then turn it off and drive from memory to see how much you have learned.",
      "Use the ghost or reference lap to compare sectors and find where you lose time.",
      "Try auto-drive only to watch a lap, and note the braking and throttle points, then turn it off.",
      "Switch all guide aids off for qualifying and for the race."
    ],
    settings: [
      { name: "Driving Line, Braking Area, Braking Indicator, Suggested Gear", effect: "Visual guides on track. Helpful when learning, but they should be off once you know the braking points." },
      { name: "Ghost or reference lap", effect: "Shows a benchmark lap for comparison. Good for finding lost time in sectors." },
      { name: "Auto-brake and Auto-Drive", effect: "The car drives itself for demonstration. Use it to learn, never to judge your own pace." }
    ],
    tips: [
      "Use guides to learn the braking points, then remove them and check that you can still hit those points.",
      "Compare sector times against the ghost, rather than the whole lap, since sectors show where you lose time.",
      "Do not copy auto-drive's exact inputs. Use them to learn the shape of the corner.",
      "Keep the ghost off in races if it distracts your attention from the road."
    ],
    mistakes: [
      "Following the racing line exactly and never learning to find your own line through a corner.",
      "Leaving auto-drive on and assuming your lap times are representative.",
      "Watching the ghost car instead of the road in a race.",
      "Turning every guide off before you have learned the track."
    ],
    wheel: "The guides are visual, so the wheel does not change what you see, but you do need to toggle them. Assign the line or ghost toggle to a d-pad direction, so you can change it in practice without going to a menu. Keep it away from the paddles. Assign it under Options, then Controller settings.",
    related: ["hud", "asm", "tcs"]
  },
  {
    id: "hud",
    title: "HUD Setup",
    kicker: "Display",
    summary: "The HUD shows what you need while driving: revs, gear, position, gaps, fuel and tyres. Set it up so you see what matters and nothing you have to decode in a corner.",
    what: [
      "The rev bar and shift light tell you when to change gear. The shift light marks the point you should shift, so it is especially useful when you are looking at the braking zone. The mini-map shows where you are on the track, and the gap timers show the time to cars ahead and behind.",
      "The fuel and tyre widgets show the remaining fuel and the tyre condition. These are the numbers that drive your pit decisions, so keep them visible in any race where they matter.",
      "The HUD can be customised in the display options. Some elements can be turned on or off. The exact list of options depends on the version of GT7, so check the display settings rather than relying on a fixed layout. A clear HUD is one of the cheapest performance gains you can make."
    ],
    how: [
      "Open the display or HUD settings from the options menu.",
      "Turn on the elements you use, such as the rev bar, shift light, gap timers, and fuel and tyre widgets.",
      "Turn off clutter you do not read in a race, such as extra text or overlays you ignore.",
      "Test the layout in practice at speed, and check that you can read the numbers without looking away from the road.",
      "Check the layout again when you change race type or car, since the numbers you need may change."
    ],
    settings: [
      { name: "Shift light and rev bar", effect: "Show when to change gear. Use them alongside the sound and the feel of the car, not instead of it." },
      { name: "Fuel and tyre widgets", effect: "Show the numbers that drive your stop strategy. Keep them on for any race with a stop." }
    ],
    tips: [
      "Keep the fuel and tyre numbers near the centre of your view, where you look during braking.",
      "Use the shift light and rev bar as a backup. Do not rely on sound alone.",
      "Turn gap timers on in races. In practice, switch off the ones you do not need, so you can focus on the car.",
      "Turn the mini-map on when you race busy or unfamiliar tracks."
    ],
    mistakes: [
      "Cluttering the screen with widgets you never read mid-race.",
      "Turning off the fuel or tyre widget, then being surprised by a late stop.",
      "Braking off a gap number instead of watching the car ahead and the corner in front of you.",
      "Setting up the HUD for one race type, then forgetting it for the next."
    ],
    wheel: "Keep the HUD clear of the place you look during braking, so the wheel rim and dash do not hide key widgets. If your wheel has its own shift lights, use them as well. Keep any HUD toggle button away from the paddles. Assign these under Options, then Controller settings.",
    related: ["mfd", "fuel", "tyres", "ghost-assists"]
  }
];

export const systemById = Object.fromEntries(SYSTEMS.map((x) => [x.id, x]));
