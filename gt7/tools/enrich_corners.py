#!/usr/bin/env python3
"""One-shot: replace terse corner `line`/`mistake` text in data/tracks/*.js.
Keyed by (track id, corner n). Run once; safe to re-run (it only swaps exact strings)."""
import os, re

E = {
 # Laguna Seca
 ('laguna','T3'): ("Brake on the slight rise, turn in once the car settles, and let it run all the way to the exit kerb. T3 sets up the short blast to T4, so exit speed beats entry speed.", "Running too deep on the brakes and missing the apex: you're slow all the way to T4."),
 ('laguna','T4'): ("Fast right with a slight crest. Lift, don't brake, turn in early and hold a constant arc to the exit kerb. Confidence corner: the car has more grip than it feels.", "Braking out of habit. A lift is enough, and braking costs about 0.3 s down the T5 run."),
 ('laguna','T5'): ("Uphill left: brake straight on the left side, wait for a late apex, then use all the exit kerb. The climb gives you extra braking grip, so you can brake later than it looks.", "Too much entry speed. You run wide and the uphill exit kills your drive."),
 ('laguna','T10'): ("Downhill right with an off-camber exit. Brake early and straight, a late turn-in, and be patient with the throttle until the car is pointed at T11.", "Early throttle on the off-camber: the rear steps out or you run onto the exit dirt."),
 ('laguna','T11'): ("The last hairpin. Brake straight and hard, use the inside kerb at a late apex, and get on the throttle as early as possible. Exit speed carries all the way down the front straight and over the T1 crest.", "Locking the inside front under late braking. Bleed the pressure off as you turn."),
 # Interlagos
 ('interlagos','T3'): ("Long, fast left onto the back straight. Stay tight on the inside and feed in throttle so you can unwind the wheel by the exit kerb. Everything you carry here runs down the Reta Oposta.", "Running wide on exit and lifting. Commit to the inside line instead."),
 ('interlagos','T4–5'): ("The main overtaking spot. Brake hard from top speed for the first left, release onto a tighter line, and treat the second left as the one that matters for exit.", "Over-driving the first left. You compromise the second and get passed back."),
 ('interlagos','T6'): ("Long downhill right. Brake lightly on entry, carry speed to a late apex, and use the camber to hold the car on the inside before powering out.", "Early throttle: the car runs out of road before Laranjinha."),
 ('interlagos','T7'): ("Medium right that sets up Pinheirinho. Turn in slightly late and finish on the left side of the road, so the left-hander that follows is straighter.", "Exiting on the wrong side. You then have to brake twice for Pinheirinho."),
 ('interlagos','T8'): ("Tight left. Brake in a straight line and rotate the car with a little trail brake. The run to Bico de Pato is short, so a tidy exit is enough.", "Too much speed and you understeer into the run-off."),
 ('interlagos','T10'): ("Fast downhill left. Lift, turn in early and let the car flow down the hill; the track drops away from you so it grips better than it looks.", "Over-slowing. Most drivers brake when a lift is enough."),
 ('interlagos','T12–15'): ("Flat-out left kinks climbing to the line. Stay smooth and use the full width. A tiny correction at 250 km/h costs more than you think.", "Running out of road on the left after a poor Junção exit."),
 # Fuji
 ('fuji','T1'): ("Biggest stop of the lap after the 1.5 km straight. Brake late and very hard in a straight line, release progressively, and turn into the right hairpin with a late apex.", "Locking the fronts. On a load cell, back off pressure as the speed drops."),
 ('fuji','T2'): ("Fast left. A lift and a confident turn-in, using the exit kerb so you're lined up for 100R.", "Over-slowing: it's quicker than it looks."),
 ('fuji','T3'): ("A long constant-radius right. Find the speed the tyres can hold and keep steady throttle all the way round, with no extra lock mid-corner.", "Early throttle: you push wide and have to lift."),
 ('fuji','T5'): ("Fast right at high speed. Flat in most Gr.3 cars. Small, smooth steering.", "Lifting: it costs speed all the way to the Dunlop chicane."),
 ('fuji','T6–7'): ("Heavy braking into a right-left chicane. Brake straight, take a tight first apex, and make the second part the priority for the climb.", "Running deep on the brakes and cutting the chicane (penalty)."),
 ('fuji','T8'): ("Uphill right in the tight final sector. Brake straight, turn in late, and let the hill help you stop.", "Too much entry speed and understeer at the apex."),
 ('fuji','T9'): ("Uphill left. Short and tight: rotate the car on the brakes and get it straight before the throttle.", "Early throttle and wheelspin out of the left."),
 ('fuji','T10'): ("The final hairpin onto the main straight. Sacrifice entry, take a late apex and be on full throttle before the exit kerb.", "Early apex: you lose speed for the whole 1.5 km straight."),
 # Daytona
 ('daytona','T1'): ("Brake off the tri-oval banking into the infield left. The banking unloads as you leave it, so start braking a little earlier than it feels.", "Braking too late from 300 km/h and running into the run-off."),
 ('daytona','T3'): ("Tight right hairpin. Brake straight, trail into a late apex, and power out towards the kink.", "Too much entry speed and understeer at the apex."),
 ('daytona','T4'): ("Fast left kink: flat or a small lift. Stay right on entry so the kink is straighter.", "Turning in early and running wide."),
 ('daytona','T5'): ("Tight right before the banking. Late apex, early throttle: exit speed decides your speed all the way round the banking and down the back straight.", "Early apex: you can't put the power down and lose the drag race."),
 ('daytona','T6'): ("Left onto the banking. Feed the throttle in as the car straightens; the banking will hold you.", "Wheelspin from too much throttle too early."),
 ('daytona','NASCAR 2'): ("Flat on the 31-degree banking. Let the car run high and stay smooth with the wheel.", "Fighting the wheel. Small inputs at high speed."),
 ('daytona','Bus Stop'): ("Chicane on the back straight. Brake hard and straight, take minimal kerb, and line up the exit for the banking.", "Cutting it for a penalty, or late braking from the tow."),
 ('daytona','NASCAR 3–4'): ("Flat through the banking and the tri-oval. Stay in the car ahead's slipstream until the braking zone.", "Pulling out of the draft too early."),
 # Road Atlanta
 ('roadatlanta','T1'): ("Fast downhill right after the straight. Brake in a straight line, turn in late, and carry speed to the exit kerb before the climb to T2.", "Overshooting the turn-in: you run wide and lose the run to the crest."),
 ('roadatlanta','T2'): ("Blind left over the crest. Aim at the left kerb, keep the wheel steady as the car goes light, and commit.", "Hesitation and lifting over the crest."),
 ('roadatlanta','T3'): ("Right after the crest. Let the car settle, then turn in and set up for the Esses.", "Running wide and ruining the Esses."),
 ('roadatlanta','T4–5'): ("Flowing downhill Esses. Minimum steering, constant throttle, and use the full width so each change of direction is gentle.", "Over-steering: sawing at the wheel scrubs speed."),
 ('roadatlanta','T6'): ("Right at the bottom of the Esses. Brake straight and get it rotated for T7.", "Too much speed from the Esses."),
 ('roadatlanta','T7'): ("Tight right onto the long back straight. Late apex and early throttle: it decides the whole straight.", "Early apex."),
 ('roadatlanta','T10'): ("Chicane at the end of the back straight. Big stop, tight first apex, and prioritise the exit towards the bridge.", "Late braking from the tow and cutting the chicane."),
 ('roadatlanta','T11'): ("Downhill right under the bridge. Turn in late and trust the grip as the track drops away.", "Running wide."),
 ('roadatlanta','T12'): ("Final downhill right onto the straight. Brake early, carry speed and be patient: it tightens.", "Early throttle and running wide off the track."),
 # Watkins Glen
 ('watkins','T1'): ("A right angle at the bottom of the hill after the main straight. Brake straight and hard, apex late and use all the exit kerb before the climb into the Esses.", "Late braking into the Ninety and losing the run up the hill."),
 ('watkins','T2–4'): ("Flat-out uphill Esses. Commit, using all the road and smooth inputs.", "Lifting in the Esses: a big time loss."),
 ('watkins','T5–6'): ("The Inner Loop (Bus Stop). Big stop, right-left, with minimal kerb.", "Cutting it for a penalty."),
 ('watkins','T7'): ("Long right of the Outer Loop. Patient throttle, with the car on the inside.", "Running wide on exit."),
 ('watkins','T8'): ("Left into the Boot. Brake straight and set up the Toe.", "Over-slowing the entry."),
 ('watkins','T9'): ("Long right hairpin (the Toe). Late apex and early throttle.", "Early apex."),
 ('watkins','T10'): ("Right (the Heel). Use the exit kerb, staying left for the Boot.", "Running wide."),
 ('watkins','T11'): ("Left (the Boot). Brake straight and rotate.", "Too much speed."),
 ('watkins','T12'): ("Fast left. A lift, then commit.", "Lifting too much."),
 ('watkins','T13'): ("Final right onto the straight. Late apex, early throttle: it decides the straight.", "Early throttle."),
 # Red Bull Ring
 ('redbullring','T1'): ("Uphill right at the end of the start straight. Brake straight, turn in late and run wide on exit for the climb to Remus.", "Late braking on lap 1 and contact."),
 ('redbullring','T3'): ("Uphill right hairpin. Brake straight, late apex, and focus on traction.", "Wheelspin on exit."),
 ('redbullring','T4'): ("Downhill right after the long straight. Main overtaking spot.", "Locking up downhill."),
 ('redbullring','T6'): ("Downhill left. Lift and turn in early.", "Running wide."),
 ('redbullring','T7'): ("Fast left (Würth). Commit.", "Over-slowing."),
 ('redbullring','T8'): ("Fast right. Flat.", "Lifting."),
 ('redbullring','T9'): ("Fast right (Rindt). Use the exit kerb.", "Running wide into the gravel."),
 ('redbullring','T10'): ("Final corner onto the straight. Late apex.", "Track limits."),
 # Catalunya
 ('catalunya','T4'): ("Right (Repsol). Turn in late; the corner opens on exit so you can unwind early.", "Early apex."),
 ('catalunya','T5'): ("Downhill left hairpin (Seat). Brake straight; trail gently.", "Locking up downhill."),
 ('catalunya','T7–8'): ("Uphill left-right. Prioritise the right for the run to Campsa.", "Over-slowing the left."),
 ('catalunya','T10'): ("Left hairpin (La Caixa). Main overtaking spot.", "Late braking."),
 ('catalunya','T11–12'): ("Left into a long right. Patient throttle.", "Running wide."),
 ('catalunya','T13'): ("Fast right. Lift, commit.", "Over-slowing."),
 ('catalunya','T14'): ("Final fast right onto the straight. Exit is everything.", "Running wide."),
 # Montreal
 ('montreal','T1–2'): ("Left into a tight right (Senna S). Prioritise the exit of the right.", "Lap 1 contact."),
 ('montreal','T3–4'): ("Right-left chicane. Minimal kerb.", "Too much kerb."),
 ('montreal','T6–7'): ("Left-right chicane. Stay off the walls.", "Running wide into the wall."),
 ('montreal','T8–9'): ("Right-left chicane. Precision over speed.", "Hitting the wall."),
 # Brands Hatch
 ('brands','T2'): ("Uphill right hairpin (Druids). Late apex for Graham Hill.", "Early apex."),
 ('brands','T3'): ("Downhill left (Graham Hill) onto Cooper Straight. Exit speed.", "Running wide."),
 ('brands','T4'): ("Left (Surtees) into the GP loop. Carry speed.", "Over-slowing."),
 ('brands','T5'): ("Fast right (Hawthorns) after the Pilgrims Drop straight. Brave entry.", "Too cautious."),
 ('brands','T6'): ("Downhill right (Westfield). Commit.", "Running wide."),
 ('brands','T7'): ("Dip and rise, then a right (Dingle Dell). Brake after the dip.", "Hitting the dip unsettled."),
 ('brands','T8'): ("Tight left (Stirlings). Brake straight.", "Late braking."),
 ('brands','T9'): ("Long right onto the straight (Clearways/Clark Curve). Patient throttle.", "Early throttle."),
 # Tsukuba
 ('tsukuba','T1–2'): ("Long right that tightens into a hairpin. Late apex.", "Early apex."),
 ('tsukuba','T3'): ("Flowing S. Carry speed.", "Over-slowing."),
 ('tsukuba','T4'): ("Long right. Patient throttle.", "Early throttle."),
 ('tsukuba','T5'): ("Hairpin onto the back straight. Late apex, traction.", "Early apex."),
 ('tsukuba','T6'): ("Tight left under the Dunlop bridge. Brake straight.", "Late braking."),
 ('tsukuba','T7'): ("Final right onto the straight. Late apex.", "Early throttle."),
 # Autopolis
 ('autopolis','T1'): ("Right after the start straight. Brake straight.", "Late braking."),
 ('autopolis','T3'): ("Downhill right. Brake early.", "Running wide."),
 ('autopolis','T4'): ("Left. Set up for the hairpin.", "Over-slowing."),
 ('autopolis','T6'): ("Left at speed. Commit.", "Running wide."),
 ('autopolis','T8'): ("Tight left. Late apex.", "Early apex."),
 ('autopolis','T10'): ("Uphill right. Brake straight.", "Too much speed."),
 ('autopolis','T12'): ("Uphill right. Smooth throttle.", "Wheelspin."),
 ('autopolis','T14'): ("Final right onto the straight. Late apex.", "Early throttle."),
 # Goodwood
 ('goodwood','T1'): ("Long double-apex right (Madgwick). Patient.", "Running wide."),
 ('goodwood','T2'): ("Flat right kink (Fordwater). Commit.", "Lifting."),
 ('goodwood','T3'): ("Right-left (St Mary's). Carry speed.", "Over-slowing."),
 ('goodwood','T4'): ("Double-apex right (Lavant) onto the straight.", "Early throttle."),
 ('goodwood','T5'): ("Fast right (Woodcote). Commit.", "Running wide."),
}

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'tracks')
def js(s): return s.replace('\\', '\\\\').replace("'", "\\'")
changed = 0
for fn in os.listdir(ROOT):
    p = os.path.join(ROOT, fn); src = open(p).read(); orig = src
    # walk track blocks: id: 'x' ... until next id: at the same indent
    for m in re.finditer(r"\n  \{\n    id: '([a-z]+)'", src):
        pass
    tracks = [(m.start(), m.group(1)) for m in re.finditer(r"\n  \{\n    id: '([a-z]+)'", src)]
    out, last = [], 0
    for idx, (start, tid) in enumerate(tracks):
        end = tracks[idx + 1][0] if idx + 1 < len(tracks) else len(src)
        block = src[start:end]
        for (t, n), (line, mistake) in E.items():
            if t != tid: continue
            pat = re.compile(r"(\{ n: '" + re.escape(n) + r"'.*?line: ')((?:[^'\\]|\\.)*)(',\s*\n?\s*mistake: ')((?:[^'\\]|\\.)*)(')", re.S)
            block, k = pat.subn(lambda mm: mm.group(1) + js(line) + mm.group(3) + js(mistake) + mm.group(5), block, count=1)
            changed += k
        out.append(src[last:start]); out.append(block); last = end
    out.append(src[last:])
    src = ''.join(out)
    if src != orig: open(p, 'w').write(src)
print('corners updated:', changed, 'of', len(E))
