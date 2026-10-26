// Circuit Experience, per track: how many sections (the count includes the
// final full-lap attack), the car GT7 hands you, and the prize money for all
// gold / all bronze. Source: Gran Turismo Wiki (fandom) Circuit Experience
// pages. GT7 doesn't publish the medal times anywhere, so the trainer asks you
// to type the gold time GT7 shows for each section: your value is the truth.
const P = (gold, bronze) => ({ gold, bronze });
const STD = P(1000000, 200000);
export const CE = {
  spa: { sections: 5, car: 'Porsche 911 RSR (991) \'17', prize: STD },
  nordschleife: { sections: 12, car: 'BMW M6 GT3 \'16', prize: P(5000000, 1000000) },
  suzuka: { sections: 6, car: 'Honda NSX Concept-GT \'16', prize: STD },
  lemans: { sections: 6, car: 'Peugeot 908 HDi FAP \'10', prize: STD },
  monza: { sections: 6, car: 'Ferrari 458 Italia GT3 \'13', prize: P(500000, 100000) },
  bathurst: { sections: 5, car: 'McLaren 650S GT3 \'15', prize: STD },
  laguna: { sections: 4, car: 'Dodge Viper Gr.4', prize: P(800000, 160000) },
  interlagos: { sections: 5, car: 'Nissan GT-R NISMO GT3 \'13', prize: STD },
  fuji: { sections: 4, car: 'Lexus RC F GT500 \'16', prize: STD },
  daytona: { sections: 4, car: 'Ford GT Race Car \'18', prize: P(800000, 160000) },
  roadatlanta: { sections: 4, car: 'Volkswagen Beetle Gr.3', prize: STD },
  watkins: { sections: 4, car: 'Genesis X GR3', prize: STD },
  redbullring: { sections: 4, car: 'Red Bull X2014 Junior', prize: STD },
  catalunya: { sections: 4, car: 'Lamborghini Huracán GT3 \'15', prize: STD },
  montreal: { sections: 5, car: 'Mercedes-AMG GT3 \'20', prize: STD },
  brands: { sections: 5, car: 'Radical SR3 SL \'13', prize: P(600000, 120000) },
  tsukuba: { sections: 4, car: 'Mitsubishi Lancer Evolution Final Gr.4', prize: P(300000, 60000) },
  autopolis: { sections: 4, car: 'Nissan GT-R NISMO GT500 \'16', prize: STD },
  goodwood: { sections: 4, car: 'Aston Martin Vantage Gr.4', prize: P(300000, 60000) },
  trialmountain: { sections: 5, car: 'Mazda RX-Vision GT3 Concept', prize: P(800000, 160000) },
  deepforest: { sections: 4, car: 'Audi R8 LMS Evo \'19', prize: STD },
  dragontrail: { sections: 4, car: 'Jaguar F-Type Gr.3', prize: STD, layout: 'Seaside' },
  sardegna: { sections: 4, car: 'Audi R18 TDI \'11', prize: STD, layout: 'Road Track A' },
  tokyo: { sections: 5, car: 'Subaru WRX Gr.3', prize: STD, layout: 'Central Clockwise' },
  highspeedring: { sections: 4, car: 'Pagani Zonda R \'09', prize: P(400000, 80000) },
  grandvalley: { sections: 4, car: 'Nissan GT-R NISMO GT3 \'18', prize: STD, layout: 'Highway 1' },
};
// Section names as GT7 lists them: numbered sectors, then the full lap.
export const sectionName = (tid, n) => (n === CE[tid].sections ? 'Full lap' : 'Sector ' + n);
