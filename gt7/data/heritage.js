// Heritage: 30 years of Gran Turismo, and the cars that explain it.

export const TIMELINE = [
  { year: 1997, title: 'Gran Turismo', platform: 'PlayStation', big: true,
    text: 'Kazunori Yamauchi\'s team (soon Polyphony Digital) spent about five years on a "Real Driving Simulator": real cars, real physics, a garage to build. It sold over 10 million copies, the best-selling PS1 game. Trial Mountain, Deep Forest, High Speed Ring and Grand Valley were born here.' },
  { year: 1999, title: 'Gran Turismo 2', platform: 'PlayStation',
    text: 'Around 650 cars on two discs, plus rally events. This is where Suzuki\'s Escudo Pikes Peak became folklore.' },
  { year: 2001, title: 'Gran Turismo 3: A-Spec', platform: 'PlayStation 2', big: true,
    text: 'The PS2 showcase. Fewer cars, a huge leap in looks and handling. The Toyota GT-One and the F1-style Formula GT became icons. It is the series\' best seller.' },
  { year: 2004, title: 'Gran Turismo 4', platform: 'PlayStation 2', big: true,
    text: 'About 700 cars, B-Spec (you as team director), Photo Mode, and the first Nürburgring Nordschleife in the series. For many, the peak of the classic era.' },
  { year: 2007, title: 'GT5 Prologue', platform: 'PlayStation 3',
    text: 'HD and online racing arrive.' },
  { year: 2008, title: 'GT Academy', platform: 'Nissan × PlayStation', big: true,
    text: 'A competition that turned GT players into real racing drivers. Lucas Ordóñez won the first edition and went on to race at Le Mans. Proof that the simulator was real enough to matter.' },
  { year: 2010, title: 'Gran Turismo 5', platform: 'PlayStation 3',
    text: 'About 1,000 cars, damage, weather, night, NASCAR and WRC, the Top Gear Test Track, and the Red Bull X2010: a no-rules car designed for GT with Adrian Newey and Sebastian Vettel.' },
  { year: 2011, title: 'Jann Mardenborough wins GT Academy', platform: 'Real life',
    text: 'A teenager from Cardiff went from GT to a Le Mans podium in 2013. His story became the 2023 film "Gran Turismo".' },
  { year: 2013, title: 'Gran Turismo 6', platform: 'PlayStation 3',
    text: 'The 15th anniversary. Vision Gran Turismo launched: manufacturers designing dream cars for GT, many later built as real show cars. Also the Goodwood hill climb.' },
  { year: 2017, title: 'Gran Turismo Sport', platform: 'PlayStation 4', big: true,
    text: 'Online-first. Sport Mode with Driver and Sportsmanship Ratings, FIA-certified championships, BoP racing classes (Gr.4, Gr.3, Gr.1), Brand Central and Scapes. Dragon Trail, Sardegna and Tokyo Expressway were added.' },
  { year: 2022, title: 'Gran Turismo 7', platform: 'PlayStation 5 / 4', big: true,
    text: 'The 25th anniversary. The Café menu books that tell car history, Legend Cars, Music Rally, DualSense haptics, and the return of Trial Mountain, Deep Forest and High Speed Ring.' },
  { year: 2023, title: 'GT Sophy, PSVR2, Spec II', platform: 'GT7 updates',
    text: 'Sony AI\'s superhuman racing agent GT Sophy arrives as an opponent. PlayStation VR2 support launches. The Spec II update brings a big physics and content refresh.' },
  { year: 2023, title: '"Gran Turismo" — the film', platform: 'Cinema',
    text: 'Neill Blomkamp\'s film of Jann Mardenborough\'s journey from player to racing driver.' },
  { year: 2026, title: 'The LMDh era', platform: 'GT7 updates 1.67–1.71',
    text: 'Porsche 963, Ferrari 499P, BMW M Hybrid V8 and Peugeot 9X8 join (1.70). New World Circuits events run at the Nordschleife, Spa, Bathurst and Suzuka.' },
];

export const CHAPTERS = [
  {
    id: 'japan', title: 'Why GT is so Japanese',
    text: [
      'GT was made in Tokyo at the peak of Japan\'s car culture. Through the 1990s Japanese makers built a run of performance cars that has never been repeated: Skyline GT-R, Supra, NSX, RX-7, Lancer Evolution, Impreza.',
      'From 1989 to 2004 they kept a "gentlemen\'s agreement" to advertise no more than 280 PS. Engines like the RB26 and 2JZ were built for far more, which is why tuning (and GT\'s tuning shops) became the culture.',
      'Best Motoring videos, Tsukuba time attacks and Initial D fed the same scene. GT turned it into a game the whole world played.',
    ],
  },
  {
    id: 'nissan', title: 'Nissan and GT',
    text: [
      'The Skyline GT-R is GT\'s signature car. The Hakosuka (1969–72) started the name. The R32 (1989) revived it and won everything: Group A, Bathurst, and the nickname "Godzilla". The R33 and R34 followed, and the R34 became the poster car of a GT generation.',
      'The relationship became official. Polyphony Digital designed the multi-function display in the R35 GT-R (2007). Nissan co-founded GT Academy (2008), which put players into real race cars at Le Mans. And Nissan is a natural Manufacturers Cup choice.',
    ],
    cars: ['hakosuka', 'fairladyz432', 'r32', 'r33', 'r34', 'gtr35nismo', 'nissanz23', 'r390', 'r92cp', 'gtrgt3'],
  },
  {
    id: 'lemans', title: 'Le Mans legends',
    text: [
      'GT has always worshipped endurance racing. The 787B (1991) is the only rotary winner. The GT-One (1998–99) was the car that should have won. The CLK-LM dominated FIA GT. The 917K, GT40, D-Type and McLaren F1 GTR are all Le Mans winners waiting in Legend Cars.',
    ],
    cars: ['mazda787b', 'gtone', 'clklm', 'porsche917k', 'gt40', 'dtype', 'mclarenf1', 'porsche962', 'ts050', 'porsche963'],
  },
  {
    id: 'icons', title: 'The JDM icons',
    text: [
      'The cars every GT garage has held at some point: Supra, NSX, RX-7, Evo, Impreza, Silvia, Roadster. Cheap to start, tunable without limit.',
    ],
    cars: ['supraa80', 'nsx', 'rx7fd', 'evo', 'impreza22b', 'silvias15', 'roadster', 'toyota2000gt', 'escudo'],
  },
];
