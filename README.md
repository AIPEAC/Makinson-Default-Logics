# Makinson Default Logics — Extension Experiment using Monte Carlo 

Empirically compare two rule-scheduling strategies for enumerating all
extensions of a Default Logic theory, implemented in SWI-Prolog.

---

## Experimental Goal

The experiment measures the cost (total applicability checks) of discovering
every distinct extension of a default-logic theory under two strategies:

### Strategy A — Permutation-based / Single Scan

1. Randomly generate a full permutation of the `n` default rules.
2. Scan the rules **once** in that order.
3. If a rule is applicable, fire it; if not, skip it and never revisit it in
   this run.
4. One permutation produces at most one extension.
5. The scan is **deterministic** — `cut` suppresses Prolog backtracking;
   no implicit search.
6. Repeat with fresh random permutations until all distinct extensions are
   observed (coupon-collector problem).

### Strategy B — Fixpoint / Full Rescan

1. Seed the belief set with one of the 2^k possible resolutions of the `k`
   conflict pairs.
2. Scan all rules in order; when any rule fires (adds a new atom), **restart
   immediately from rule 1** (no Prolog backtracking).
3. Repeat until a complete pass adds nothing — that is the fixpoint extension.
4. Each construction is **deterministic**.
5. Enumerate all extensions by running one fixpoint per seed; deduplicate
   with `msort/2` + `memberchk/2`.

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

| Strategy | Metric |
|----------|--------|
| A | Average permutations required to observe all distinct extensions (over MC runs) |
| A | Average total applicability checks (over MC runs) |
| B | Total fixpoint constructions needed to enumerate all extensions |
| B | Total applicability checks across all constructions |

Extension deduplication uses `msort/2` (canonical sorted form) and
`memberchk/2` (membership test before inserting).

---

## Configuration

Edit the top of `experiment.pl`:

| Predicate | Default | Description |
|-----------|---------|-------------|
| `n_values/1` | `[8,10,12,14,16,18,20]` | List of rule-counts to sweep |
| `k_for_n/2` | `max(2, N // 4)` | Conflict pairs for a theory of size N |
| `mc_runs/1` | `10` | Monte Carlo repetitions for Strategy A |
| `max_perms/1` | `200000` | Safety cap on Strategy-A permutations per trial |

---

## Running the Experiment

### Directly with SWI-Prolog

```bash
swipl -s experiment.pl
```

### With Docker (pull from GHCR)

```bash
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

Monte Carlo runs per n (Strategy A) : 10
Max permutations cap per A-trial    : 200000

-----------------------------------------------------------------
n=20  |  conflict_pairs=5  |  extensions=32
  [B] constructions=32   total_checks=5600   found=32/32
  [A] avg_perms=119.4   avg_checks=2388.0   cap_hits=0/10
  ratio A_checks/B_checks=0.43
```

### Interpreting the Results

* **Strategy B** runs exactly 2^k fixpoint constructions — one per extension.
  Each construction involves repeated passes over all `n` rules (restarting on
  every new atom), so its per-construction cost grows as O(n × n_indep).

* **Strategy A** exhibits coupon-collector growth: as `k` (and therefore the
  number of extensions) increases, the expected number of random permutations
  needed to cover all extensions grows as O(2^k · k · ln 2), making it scale
  super-linearly with the number of extensions.  Each permutation costs exactly
  `n` applicability checks (one pass).

* Watching the metrics across different `n` values shows that both the
  permutation count for Strategy A and the total-check count grow with `n`,
  empirically confirming the exponential (coupon-collector) growth of Strategy A
  versus the polynomial-per-extension cost of Strategy B.

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
* No external services or network access needed
