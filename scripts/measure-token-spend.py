#!/usr/bin/env python3
"""Measure where Claude Code token spend actually goes, from your own transcripts.

Reads ~/.claude/projects/**/*.jsonl (your local session records; nothing leaves
the machine) and prints the tables recorded in docs/reference/model-policy.md.
Run it before acting on any cost claim in that file — including this repo's.

    python3 scripts/measure-token-spend.py [--root DIR]

Two things this deliberately does NOT do, because both produced wrong numbers
in the first pass and the errors survived review:

  * It does not count file-read volume from the `Read` tool alone. Agents read
    files through Bash (`cat`, `head`, `sed -n`, `tail`) constantly, and that
    output lands in the Bash bucket. Both paths are summed.
  * It does not treat `toolUseResult` json length as a token count. The largest
    of those records are base64 screenshots, where chars/4 overstates tokens by
    orders of magnitude. Only text reaching the model's context is counted, and
    image blocks are reported separately as a count.
"""
import argparse, collections, glob, json, os, statistics as st

# $/MTok (input, output), Anthropic first-party list rates. Unknown -> Opus tier.
PRICES = {
    'claude-opus-5': (5, 25), 'claude-opus-4-8': (5, 25), 'claude-opus-4-7': (5, 25),
    'claude-opus-4-6': (5, 25), 'claude-fable-5-1': (10, 50), 'claude-fable-5': (10, 50),
    'claude-sonnet-5': (2, 10), 'claude-sonnet-4-6': (3, 15),
    'claude-haiku-4-5-20251001': (1, 5), 'claude-haiku-4-5': (1, 5),
}
# Bash commands whose output is a file read rather than a build/test/git result.
READ_CMDS = ('cat ', 'head ', 'tail ', 'sed -n', 'less ', 'more ', 'bat ')

def cost(model, cc, cr, inp, out):
    """Cache creation bills at 1.25x input, cache reads at 0.10x input."""
    i, o = PRICES.get(model, (5, 25))
    return (cc * 1.25 * i + cr * 0.10 * i + inp * i + out * o) / 1e6

def text_len(content):
    """Chars of TEXT a tool result contributed to context. Images excluded."""
    if isinstance(content, str):
        return len(content), 0
    if isinstance(content, list):
        chars = sum(len(b.get('text', '')) for b in content
                    if isinstance(b, dict) and b.get('type') == 'text')
        imgs = sum(1 for b in content if isinstance(b, dict) and b.get('type') == 'image')
        return chars, imgs
    return 0, 0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=os.path.expanduser('~/.claude/projects'))
    args = ap.parse_args()

    locus = collections.defaultdict(collections.Counter)
    locus_cost, ctx = collections.Counter(), collections.defaultdict(list)
    tool_chars, tool_calls = collections.Counter(), collections.Counter()
    file_read_chars = collections.Counter()   # 'Read' | 'Bash'
    images = 0
    growth = collections.defaultdict(list)    # session -> [(turn_no, context)]

    files = glob.glob(os.path.join(args.root, '**', '*.jsonl'), recursive=True)
    for f in files:
        sid, id2 = os.path.basename(f)[:8], {}
        turn = 0
        for line in open(f, errors='replace'):
            try:
                d = json.loads(line)
            except Exception:
                continue
            msg = d.get('message') or {}
            side = bool(d.get('isSidechain'))

            if d.get('type') == 'assistant':
                u = msg.get('usage') or {}
                if u:
                    cc = u.get('cache_creation_input_tokens', 0) or 0
                    cr = u.get('cache_read_input_tokens', 0) or 0
                    ip = u.get('input_tokens', 0) or 0
                    op = u.get('output_tokens', 0) or 0
                    where = 'subagent' if side else 'interactive session'
                    locus[where]['turns'] += 1
                    locus_cost[where] += cost(msg.get('model') or '?', cc, cr, ip, op)
                    for k, v in (('cc', cc), ('cr', cr), ('out', op)):
                        locus[where][k] += v
                    ctx[where].append(cc + cr + ip)
                    if not side:
                        turn += 1
                        growth[sid].append((turn, cc + cr + ip))
                for b in (msg.get('content') or []):
                    if isinstance(b, dict) and b.get('type') == 'tool_use':
                        id2[b.get('id')] = (b.get('name', '?'),
                                            (b.get('input') or {}).get('command', ''))
                        tool_calls[b.get('name', '?')] += 1

            elif d.get('type') == 'user':
                for b in (msg.get('content') or []):
                    if not (isinstance(b, dict) and b.get('type') == 'tool_result'):
                        continue
                    name, cmd = id2.get(b.get('tool_use_id'), ('?', ''))
                    n, imgs = text_len(b.get('content'))
                    tool_chars[name] += n
                    images += imgs
                    if name == 'Read':
                        file_read_chars['Read'] += n
                    elif name == 'Bash' and any(k in cmd for k in READ_CMDS):
                        file_read_chars['Bash'] += n

    def tok(c):
        return c / 4  # chars -> tokens, rough
    def k(n):
        return f"{n/1000:,.0f}k" if n < 1e6 else f"{n/1e6:,.2f}M"

    cc = sum(v['cc'] for v in locus.values())
    cr = sum(v['cr'] for v in locus.values())
    amp = cr / cc if cc else 0
    total = sum(locus_cost.values())

    print(f"transcripts: {len(files)}   turns: {sum(v['turns'] for v in locus.values()):,}")
    print(f"cache_creation {k(cc)}   cache_read {k(cr)}   "
          f"average re-read amplification {amp:.1f}x\n")

    print("WHERE THE WORK RAN")
    print(f"  {'':22} {'share':>7} {'turns':>7} {'$/turn':>8} {'median ctx/turn':>16}")
    for w, c in locus_cost.most_common():
        t = locus[w]['turns']
        print(f"  {w:22} {c/total*100:>6.1f}% {t:>7} {c/t:>8.3f} "
              f"{k(st.median(ctx[w])):>16}")

    print("\nWITHIN-SESSION GROWTH (main thread, sessions with >=100 turns)")
    print(f"  {'session':10} {'turns':>7} {'first 25':>9} {'last 25':>9} {'growth':>7}")
    gs = []
    for sid, v in sorted(growth.items(), key=lambda x: -len(x[1])):
        if len(v) < 100:
            continue
        a = st.median([c for _, c in v[:25]])
        b = st.median([c for _, c in v[-25:]])
        gs.append(b / max(a, 1))
        print(f"  {sid:10} {len(v):>7} {k(a):>9} {k(b):>9} {b/max(a,1):>6.1f}x")
    if len(gs) > 1:
        print(f"  median growth excluding the largest session: "
              f"{st.median(sorted(gs)[:-1]):.1f}x")

    print("\nTOOL RESULT TEXT REACHING CONTEXT")
    tt = sum(tool_chars.values())
    print(f"  {'tool':30} {'calls':>7} {'~tokens':>9} {'share':>7}")
    for name, n in tool_chars.most_common(8):
        print(f"  {name[:30]:30} {tool_calls.get(name,0):>7} {k(tok(n)):>9} "
              f"{n/tt*100:>6.1f}%")
    print(f"  {'TOTAL (text only)':30} {sum(tool_calls.values()):>7} {k(tok(tt)):>9}")
    print(f"  image blocks returned (not counted above): {images}")

    fr = sum(file_read_chars.values())
    print("\nFILE-READ VOLUME — the number a read-shunt could address")
    for src, n in file_read_chars.most_common():
        print(f"  via {src:6} {k(tok(n)):>9}")
    print(f"  total     {k(tok(fr)):>9}  ({fr/tt*100:.0f}% of tool text)")
    print(f"  amplified by {amp:.1f}x re-reads: {k(tok(fr)*amp)} of {k(cr)} cache_read"
          f"  = {tok(fr)*amp/cr*100:.2f}% of spend")

if __name__ == '__main__':
    main()
