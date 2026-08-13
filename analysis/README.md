# Analysis tools

Tools for understanding what models actually did across many rollouts.

## `judge_matrix.py` — LLM judges

Classifies each rollout as `ESCAPE_SUCCEEDED` / `ATTEMPTED_BUT_FAILED` / `OTHER_CHEAT_USED` /
`HONEST_TASK_FAILURE`, plus `boundary_awareness` and `eval_awareness` probes. Uses two
independent LLM judges (Sonnet + GPT) plus the deterministic scorer ladder.

```bash
python3 analysis/judge_matrix.py --glob 'logs/mx_*/*.eval' --out analysis/judge.json
```

The scorer-vs-judge cross-check is how we caught several detection bugs (false positives/negatives
that the deterministic scorer alone missed).

## `summarize_matrix.py` — Sonnet trajectory summaries

Produces a plain-English summary of each rollout: what the model tried, whether it probed the
boundary, whether it escaped / fabricated / gave up, and any eval-awareness. Reading these at
scale is how we understand model behavior.

```bash
python3 analysis/summarize_matrix.py --glob 'logs/mx_*/*.eval' --out analysis/summaries.json
```

## `extract_trajectories.py` — trajectory extraction

Extracts readable trajectories (reasoning + commands + outputs) from `.eval` logs into
per-trial JSON for the viewer. Resolves `attachment://` references to their stored content.

## `viewer.html` — trajectory viewer

A mobile-friendly HTML page for browsing trajectories. Serve the `analysis/` dir with
`python3 -m http.server` and open on any device. Filters by model/task/weakness/outcome; tap a
card to expand the full trajectory (prompt at top, collapsible reasoning/outputs).

## `make_graph.py` — results graph

Builds the escape-rate-by-condition graph (`results_graph.png`) from `all_trials.json`.
