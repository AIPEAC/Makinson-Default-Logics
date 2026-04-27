# Makinson Default Logics — Extension Enumeration Experiment

Empirically compares three extension-construction schedules for Default Logic,
implemented in SWI-Prolog.

---

## Experimental Goal

The experiment measures construction cost (total applicability checks) under
three strategies:

### Strategy 0 — Reiter baseline (deterministic Xi sweep)

1. Enumerate Xi seeds in binary order: `000...0`, `000...1`, ..., `111...1`.
2. For each Xi, run deterministic Reiter fixpoint closure.
3. No random Xi resampling is used in Strategy 0.

### Strategy A — Makinson with priority skipped-queue

1. Draw an initial random rule sequence (permutation).
2. Process queue; when a rule is skipped, store it in a priority skipped-list
  where older skipped rules have higher priority.
3. Whenever `IN` updates (a rule fires), revisit skipped rules first.
4. Constructions are drawn through a permutation process tree.

### Strategy B — Makinson with FIFO skipped-queue

1. Draw an initial random rule sequence (permutation).
2. Process queue; skipped rules are moved to queue tail (FIFO behavior).
3. Terminate a construction on a full no-progress round.
4. Constructions are drawn through the same permutation process tree.

### Process-tree branch cutoff (A/B)

For A/B, the permutation tree is pruned semantically: once a prefix has
already decided all conflict-pair choices, the remaining order is treated as
equivalent and that subtree is closed early.

---

## Theory Model

Each default rule is represented as:

```prolog
rule(Prereqs, Justifications, Conclusion)
```

| Field            | Meaning                                              |
|------------------|------------------------------------------------------|
| `Prereqs`        | List of atoms that must be in the current belief set |
| `Justifications` | List of atoms that must **not** be in the belief set |
| `Conclusion`     | Single atom added to the belief set when rule fires  |

A rule is **applicable** in belief set `S` iff all prerequisites are in `S`
and none of the justifications are in `S`.  Checking applicability counts as
one atomic operation.

The generated theory contains:

* **`k` conflict pairs** — `rule([], [neg_I], pos_I)` and
  `rule([], [pos_I], neg_I)` — which yield exactly **2^k distinct extensions**.
* **`n − 2k` independent rules** — `rule([], [], indep_I)` — which always
  fire and appear in every extension.

---

## Metrics Collected

For each strategy and each `n`:

1. `avg_trials`: average number of constructions attempted over `mc_runs`.
2. `avg_checks`: average total applicability checks over `mc_runs`.
3. `cap_hits`: how many runs terminated due to `max_trials` cap.

Ratios versus Strategy 0 are also printed:

1. `A_checks / 0_checks`
2. `B_checks / 0_checks`

---

## Configuration

Edit the top of `experiment.pl`:

| Predicate | Default | Description |
|-----------|---------|-------------|
| `n_values/1` | `[4,6,8]` | List of rule-counts to sweep |
| `k_for_n/2` | `max(2, N // 4)` | Conflict pairs for a theory of size N |
| `mc_runs/1` | `10` | Number of repeated runs used to average each strategy |
| `max_trials/1` | `200000` | Safety cap on constructions per strategy run |

---

## Running the Experiment

### Directly with SWI-Prolog

```bash
swipl -s experiment.pl
```

### With Docker (pull from GHCR)

```bash
sh ./run.sh

# equivalent manual commands:
docker compose pull
docker compose run --rm experiment
```

### With Docker (local build, optional)

```bash
docker build -t default-logic-exp .
docker run --rm default-logic-exp
```

The default container source is GitHub Container Registry:
`ghcr.io/aipeac/makinson-default-logics:latest`.

### Via GitHub Actions

The workflow at `.github/workflows/experiment.yml` runs automatically on every
`push` and prints results to the workflow log.

---

## Sample Output

```
=================================================================
Default Logic Extension-Enumeration Experiment
=================================================================

Monte Carlo runs per n (A/B only)      : 10
Strategy 0 Xi order                    : 0..(2^k-1)
Max constructions per strategy run     : 200000

-----------------------------------------------------------------
n=8  |  conflict_pairs=2  |  extensions=4
  [0] avg_trials=4.0   avg_checks=96.0   cap_hits=0/10
  [A] avg_trials=...   avg_checks=...    cap_hits=.../10
  [B] avg_trials=...   avg_checks=...    cap_hits=.../10
  ratio A_checks/0_checks=...   B_checks/0_checks=...
```

### Interpreting the Results

* **Strategy 0** no longer pays coupon-collector overhead from Xi resampling,
  because Xi is enumerated once in increasing binary order.

* **A/B** traverse permutation space via a process tree. Their branch-pruning
  rule can collapse many permutations that are semantically equivalent after a
  deciding prefix.

* If `cap_hits` is nonzero, that strategy reached `max_trials` before fully
  exhausting its current search process in that run.

---

## Repository Structure

```
.
├── experiment.pl                   # Core SWI-Prolog experiment
├── Dockerfile                      # Docker image (based on swipl:latest)
├── .github/
│   └── workflows/
│       └── experiment.yml          # GitHub Actions workflow
└── README.md
```

---

## Requirements

* **SWI-Prolog ≥ 8.0** (uses `library(lists)`, `library(random)`,
  `library(apply)`)
* Or **Docker** (compose directly from remote)
