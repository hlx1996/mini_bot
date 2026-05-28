#!/usr/bin/env python3
"""
lib/memory_search.py — BM25 + char-bigram ranking over mini_bot memory lines.

Pure stdlib. Works for Chinese (char-bigrams) and English (words).
Usage:
    memory_search.py <query> <file1> [<file2> ...]
Output:
    Top-K matching lines, one per line, sorted by score desc.
    File-tag prefix per line: [chat] or [global] (file basename heuristic).
"""
import math, re, sys
from pathlib import Path

TOPK = 8
MIN_SCORE = 0.5

WORD = re.compile(r"[A-Za-z0-9_]+")
CJK  = re.compile(r"[\u4e00-\u9fff]")

def tokenize(text: str):
    text = text.lower()
    toks = []
    toks += WORD.findall(text)
    # char-bigrams for Chinese
    cjk_chars = "".join(CJK.findall(text))
    for i in range(len(cjk_chars) - 1):
        toks.append(cjk_chars[i:i+2])
    return toks

def bm25_rank(query, docs, k1=1.5, b=0.75):
    """Return list of (score, doc_index) sorted desc."""
    if not docs:
        return []
    tok_docs = [tokenize(d) for d in docs]
    doc_lens = [len(t) for t in tok_docs]
    avgdl = sum(doc_lens) / len(doc_lens) if doc_lens else 1
    n_docs = len(docs)
    # df
    df = {}
    for toks in tok_docs:
        for w in set(toks):
            df[w] = df.get(w, 0) + 1
    q_toks = tokenize(query)
    if not q_toks:
        return []
    scores = []
    for i, toks in enumerate(tok_docs):
        if not toks:
            scores.append((0.0, i)); continue
        tf = {}
        for w in toks: tf[w] = tf.get(w, 0) + 1
        s = 0.0
        for q in q_toks:
            if q not in tf: continue
            idf = math.log((n_docs - df[q] + 0.5) / (df[q] + 0.5) + 1)
            denom = tf[q] + k1 * (1 - b + b * doc_lens[i] / avgdl)
            s += idf * tf[q] * (k1 + 1) / denom
        scores.append((s, i))
    scores.sort(reverse=True)
    return scores

def main():
    if len(sys.argv) < 3:
        print("usage: memory_search.py <query> <file1> [<file2> ...]", file=sys.stderr)
        sys.exit(2)
    query = sys.argv[1]
    files = sys.argv[2:]
    lines = []
    tags  = []
    for f in files:
        p = Path(f)
        if not p.exists(): continue
        tag = "global" if "global" in p.name else "chat"
        try:
            for ln in p.read_text(errors="ignore").splitlines():
                ln = ln.strip()
                if ln:
                    lines.append(ln); tags.append(tag)
        except Exception:
            pass
    if not lines:
        return
    ranked = bm25_rank(query, lines)
    shown = 0
    for score, idx in ranked:
        if shown >= TOPK or score < MIN_SCORE: break
        prefix = "[GLOBAL] " if tags[idx] == "global" else ""
        print(f"{prefix}{lines[idx]}  (score={score:.2f})")
        shown += 1

if __name__ == "__main__":
    main()
