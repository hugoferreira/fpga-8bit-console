#!/usr/bin/env python3
"""Selection census: classify every SB_LUT4 by boolean function class.

Answers the question the LUT4 count structurally cannot: how much of the mapped
area is *residual selection* — 2:1 muxes that survived covering as whole cells
because the mapper found no adjacent cut with spare inputs to absorb them into.
THE LAW (skill §4) says selection is free *inside* arithmetic; this tool counts
the selection that is NOT inside anything: pure fabric-routing cost, and prices
it per select net so the ranking can seed a hypothesis pool.

Usage:
    python3 tools/psg_mux_census.py <netlist.json>

Feed it the deterministic -noabc netlist for a rank-stable, cleanly-named
attribution (spread 0 over renames, see detfloor.sh), or build/targets/psg.json
for the shipped abc9 picture (fractions are one noisy draw; net names mangled).

Classes:
    mux2       f == s ? a : b, plain nets            -> pure selection cell
    mux2_inv   same with an inverted arm             -> pure selection cell
    mux_mixed  4-var f == s ? literal : g(two vars)  -> half-absorbed selection
    wire       buffer/inverter                       -> pure routing
    logic2/3/4 everything else, by live support size

Baseline at fingerprint e004a57e4ee8 @ a121c03 (H161):
    -noabc floor (8,282 LUT): mux2 2,008 (24.2%)  mux_mixed 1,483  wire 445
    abc9 shipped (6,300 LUT): mux2+inv  997 (15.8%)  mux_mixed 1,626  wire 127
    i.e. abc9 absorbs ~half the floor's pure muxes; ~1,000 shipped cells remain
    pure selection. Top -noabc select nets: u_walk.cap 68, u_seq chain 52,
    u_walk.bl_cnt 51, dq_old_ctx 42, addr 38, s_snd_wt 35.

Caveats. A pure-mux LUT is attributed cost, not refundable cost — some
selection is semantically required. Per-net counts are ceilings for ranking
only; honest pricing is ablation-to-replacement (skill §5), and the whole-PSG
gate (`make area-psg`) remains the only verdict. Constant-tied inputs are
cofactored out before classification (LUT_INIT is variable-width; a '0'-tied
input otherwise masquerades as live support and everything reads logic4).
"""
import json
import sys
import collections


def classify_lut(init_str, conns):
    """Return (class, select_I_port_or_None) for one SB_LUT4.

    conns: the four I0..I3 connection bits (int net id, or '0'/'1'/'x').
    """
    v = int(init_str, 2)
    tt = [(v >> i) & 1 for i in range(16)]

    live, fixed = [], {}
    for i, cb in enumerate(conns):
        if isinstance(cb, str):
            fixed[i] = 1 if cb == "1" else 0
        else:
            live.append(i)

    k = len(live)
    sub = []
    for x in range(1 << k):
        full = 0
        for j, i in enumerate(live):
            if (x >> j) & 1:
                full |= 1 << i
        for i, val in fixed.items():
            if val:
                full |= 1 << i
        sub.append(tt[full])

    sup = [j for j in range(k)
           if any(sub[x] != sub[x ^ (1 << j)] for x in range(1 << k))]
    ks = len(sup)
    stt = []
    for x in range(1 << ks):
        full = 0
        for j, i in enumerate(sup):
            if (x >> j) & 1:
                full |= 1 << i
        stt.append(sub[full])
    live_sup = [live[j] for j in sup]

    if ks == 0:
        return "const", None
    if ks == 1:
        return "wire", None
    if ks == 2:
        return "logic2", None
    if ks == 3:
        for s in range(3):
            rest = [r for r in range(3) if r != s]
            for a, b in (tuple(rest), tuple(rest[::-1])):
                for ainv in (0, 1):
                    for binv in (0, 1):
                        if all(stt[x] == ((((x >> a) & 1) ^ ainv)
                                          if (x >> s) & 1
                                          else (((x >> b) & 1) ^ binv))
                               for x in range(8)):
                            cls = "mux2" if ainv == 0 and binv == 0 else "mux2_inv"
                            return cls, live_sup[s]
        return "logic3", None

    for s in range(4):
        rem = [j for j in range(4) if j != s]
        cof_sups = []
        for val in (0, 1):
            ctt = []
            for x in range(8):
                full = val << s
                for j, i in enumerate(rem):
                    if (x >> j) & 1:
                        full |= 1 << i
                ctt.append(stt[full])
            cof_sups.append(sum(1 for j in range(3)
                                if any(ctt[x] != ctt[x ^ (1 << j)]
                                       for x in range(8))))
        if min(cof_sups) <= 1 <= max(cof_sups):
            return "mux_mixed", live_sup[s]
    return "logic4", None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[0] +
                 "\nusage: psg_mux_census.py <netlist.json>")
    mods = json.load(open(sys.argv[1]))["modules"]
    mod = next((m for n, m in mods.items() if n.startswith("target_")), None)
    if mod is None:
        mod = max(mods.values(), key=lambda m: len(m.get("cells", {})))

    netnames = {}
    for nname, nn in mod.get("netnames", {}).items():
        for b in nn["bits"]:
            if isinstance(b, int) and b not in netnames:
                netnames[b] = nname

    counts = collections.Counter()
    sel_rank = collections.Counter()
    for c in mod["cells"].values():
        if c["type"] != "SB_LUT4":
            continue
        conns = [c["connections"].get(f"I{i}", ["0"])[0] for i in range(4)]
        cls, sport = classify_lut(c["parameters"]["LUT_INIT"], conns)
        counts[cls] += 1
        if sport is not None and cls in ("mux2", "mux2_inv"):
            selbit = conns[sport]
            sel_rank[netnames.get(selbit, f"bit{selbit}")] += 1

    total = sum(counts.values())
    print(f"SB_LUT4 cells: {total}")
    for cls in ("mux2", "mux2_inv", "mux_mixed", "wire", "const",
                "logic2", "logic3", "logic4"):
        n = counts[cls]
        print(f"  {cls:10s} {n:6d}  {100 * n / max(total, 1):5.1f}%")
    print("\nTop select nets driving pure-mux LUTs:")
    for net, n in sel_rank.most_common(30):
        print(f"  {n:5d}  {net}")


if __name__ == "__main__":
    main()
