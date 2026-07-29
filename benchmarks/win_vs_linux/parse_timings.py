#!/usr/bin/env python3
"""
Parse PICLas benchmark timings from reggie run directories.

reggie (invoked with -e ... -s) writes every run's full stdout to a file named
`std.out` inside that run's directory. We read those files directly -- more
robust than scraping the ANSI-coloured summary table -- and pull three facts
straight from PICLas' own output:

    ranks    <- '#Procs     :    N.000E+00'
    seconds  <- 'PICLAS FINISHED! [ N sec ]'          (pure solve, no process spawn)
    solver   <- 'Iterative solver: cg with gamg ...'  -> GAMG   (PrecondType=4)
                'Iterative solver: pipecg with bjacobi'-> BJACOBI(PrecondType=2)
                (absent for DSMC)

Usage:
    parse_timings.py --os win --out results/win_timings.csv \
        --case pic=results/run_pic --case dsmc=results/run_dsmc

    # side-by-side once both OSes have a CSV:
    parse_timings.py --compare results/win_timings.csv results/linux_timings.csv
"""
import argparse
import csv
import os
import re
import sys
from collections import defaultdict

RE_PROCS  = re.compile(r'#Procs\s*:\s*([0-9.]+[Ee][+\-]?[0-9]+|[0-9.]+)')
RE_FIN    = re.compile(r'PICLAS FINISHED!\s*\[\s*([0-9.]+)\s*sec')
RE_GAMG   = re.compile(r'cg with gamg', re.I)
RE_BJAC   = re.compile(r'with bjacobi', re.I)


def scan_case(label, root):
    """Yield one record dict per PICLas run found under `root`."""
    if not os.path.isdir(root):
        print(f"  ! case '{label}': directory not found: {root}", file=sys.stderr)
        return
    for dirpath, _dirs, files in os.walk(root):
        if 'std.out' not in files:
            continue
        text = _read(os.path.join(dirpath, 'std.out'))
        m_fin = RE_FIN.search(text)
        m_pro = RE_PROCS.search(text)
        if not m_fin or not m_pro:
            continue  # a crashed / partial run -- skip, do not fabricate a time
        ranks = int(round(float(m_pro.group(1))))
        secs  = float(m_fin.group(1))
        if RE_GAMG.search(text):
            solver = 'GAMG'
        elif RE_BJAC.search(text):
            solver = 'BJACOBI'
        else:
            solver = '-'
        yield {'case': label, 'ranks': ranks, 'solver': solver, 'sec': secs}


def _read(path):
    with open(path, 'r', errors='replace') as f:
        return f.read()


def collect(cases):
    rows = []
    for label, root in cases:
        found = list(scan_case(label, root))
        rows.extend(found)
        print(f"  case '{label}': {len(found)} completed run(s) in {root}")
    # stable order: case, solver, ranks
    rows.sort(key=lambda r: (r['case'], r['solver'], r['ranks']))
    return rows


def write_csv(rows, os_tag, out):
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    with open(out, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['os', 'case', 'solver', 'ranks', 'sec'])
        for r in rows:
            w.writerow([os_tag, r['case'], r['solver'], r['ranks'], f"{r['sec']:.3f}"])
    print(f"\nWrote {len(rows)} rows -> {out}")


def report(rows, os_tag):
    """Print scaling + GAMG-speedup tables to the console."""
    # index: (case, solver) -> {ranks: sec}
    idx = defaultdict(dict)
    for r in rows:
        idx[(r['case'], r['solver'])][r['ranks']] = r['sec']

    print(f"\n================ {os_tag} :: wall time [s] and strong scaling ================")
    for (case, solver), byrank in sorted(idx.items()):
        ranks = sorted(byrank)
        base = byrank[ranks[0]] if ranks else None
        tag = f"{case}/{solver}" if solver != '-' else case
        print(f"\n  {tag}")
        print(f"    {'ranks':>6} {'sec':>10} {'speedup':>9} {'parEff':>8}")
        for n in ranks:
            sp = base / byrank[n] if byrank[n] else float('nan')
            eff = sp / (n / ranks[0]) if n else float('nan')
            print(f"    {n:>6} {byrank[n]:>10.2f} {sp:>8.2f}x {eff:>7.0%}")

    # GAMG vs BJACOBI, per rank (PIC only)
    gamg = idx.get(('pic', 'GAMG'), {})
    bjac = idx.get(('pic', 'BJACOBI'), {})
    common = sorted(set(gamg) & set(bjac))
    if common:
        print(f"\n================ {os_tag} :: GAMG speedup (PrecondType 4 vs 2) ================")
        print(f"    {'ranks':>6} {'bjacobi[s]':>11} {'gamg[s]':>9} {'speedup':>9}")
        for n in common:
            print(f"    {n:>6} {bjac[n]:>11.2f} {gamg[n]:>9.2f} {bjac[n]/gamg[n]:>8.2f}x")


def compare(csv_a, csv_b):
    def load(p):
        d = {}
        with open(p) as f:
            for row in csv.DictReader(f):
                d[(row['case'], row['solver'], int(row['ranks']))] = (row['os'], float(row['sec']))
        return d
    A, B = load(csv_a), load(csv_b)
    keys = sorted(set(A) & set(B))
    if not keys:
        print("No overlapping (case,solver,ranks) between the two CSVs.", file=sys.stderr)
        return
    osA = next(iter(A.values()))[0]
    osB = next(iter(B.values()))[0]
    print(f"\n================ {osA} vs {osB} ================")
    print(f"    {'case':>6} {'solver':>8} {'ranks':>6} {osA+'[s]':>10} {osB+'[s]':>10} {osB+'/'+osA:>10}")
    for case, solver, ranks in keys:
        a = A[(case, solver, ranks)][1]
        b = B[(case, solver, ranks)][1]
        ratio = b / a if a else float('nan')
        print(f"    {case:>6} {solver:>8} {ranks:>6} {a:>10.2f} {b:>10.2f} {ratio:>9.2f}x")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--os', default='host', help="OS tag written into the CSV (e.g. win, linux)")
    ap.add_argument('--out', help="output CSV path")
    ap.add_argument('--case', action='append', default=[], metavar='LABEL=DIR',
                    help="a case label and its reggie output dir; repeatable")
    ap.add_argument('--compare', nargs=2, metavar=('CSV_A', 'CSV_B'),
                    help="print a side-by-side comparison of two timing CSVs and exit")
    args = ap.parse_args()

    if args.compare:
        compare(*args.compare)
        return

    if not args.case or not args.out:
        ap.error("need --out and at least one --case LABEL=DIR (or use --compare)")

    cases = []
    for spec in args.case:
        if '=' not in spec:
            ap.error(f"--case must be LABEL=DIR, got: {spec}")
        label, d = spec.split('=', 1)
        cases.append((label, d))

    rows = collect(cases)
    if not rows:
        print("No completed runs found. Did the benchmark run and did reggie use -s?", file=sys.stderr)
        sys.exit(2)
    write_csv(rows, args.os, args.out)
    report(rows, args.os)


if __name__ == '__main__':
    main()
