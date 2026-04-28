# Makinson Default Logics — Extension Enumeration Experiment


Empirically compares three extension-construction schedules for propositional
default theories, implemented in SWI-Prolog.

---


## Experimental Setup (short)

We compare three deterministic construction schedules for propositional
default theories that contain $k$ conflict pairs (giving $2^k$ extensions)
plus independent rules. The strategies are:

- Strategy 0: enumerate Xi seeds in binary order and run Reiter-style
  fixpoint closure for each seed (no resampling).
- Strategy A: permutation-driven single-scan schedule with a priority
  skipped-queue (older skipped rules revisited first).
- Strategy B: permutation-driven single-scan schedule with a FIFO skipped-queue
  (skipped rules move to the tail; terminate on a full no-progress round).

For A/B we maintain a process tree of prefix permutations and apply a
semantic cutoff: when a prefix already decides every conflict-pair, the
remaining order is equivalent and that subtree is closed.

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


### Analysis (mathematical summary)

Let $K$ be the number of conflict pairs and $m=2^K$ the number of extensions.

- Strategy 0 (deterministic Xi sweep): covers $m$ seeds exactly once, so the
  number of constructions is $m$ (or the `max_trials` cap if smaller). Its
  total applicability checks scale as $m\cdot C_0$, where $C_0$ is the per-seed
  cost of Reiter's fixpoint closure (depends on $n$ and the independent rules).

- Strategy A (permutation single-scan, conventional agenda-style): when
  implemented as random permutations the classical coupon-collector model
  applies: the expected number of random permutations to observe all $m$
  extensions is

$$
\mathbb{E}[T] = m\cdot H_m = m\sum_{i=1}^m \frac{1}{i} \approx m(\ln m + \gamma),
$$

  where $H_m$ is the $m$th harmonic number and $\gamma$ is the Euler–Mascheroni
  constant. This is why random-resample A appears to require substantially more
  trials than $m$.

- Strategy B (FIFO skipped-queue): like A it explores the permutation tree,
  but its FIFO policy plus the semantic tree cutoff tend to produce fewer
  distinct constructions for the same amount of prefix exploration. Empirically
  this reduces redundant scans compared to naive random permutations used in A
  because A is essentially performing collision-prone sampling in a large
  discrete space.

Comparative intuition:

- A (conventional agenda/permutation sampling) is equivalent to many
  production-system/agenda conflict-resolution strategies (see Forgy, OPS5/Rete
  literature) where conflict resolution order matters and can dominate
  performance. Random permutation sampling makes A pay coupon-collector costs
  of order $\Theta(m\log m)$ in expectation.
- B gains from queueing discipline and the permutation-tree semantic cutoff;
  it therefore avoids many redundant full scans that A would revisit under
  random sampling. For our synthetic theory family this gives lower total
  applicability checks in most parameter ranges.

Practical takeaway: if you want exact one-shot coverage of all Xi without
sampling overhead, use Strategy 0 (deterministic enumeration). If you must
explore permutation-induced constructions (A/B), queue discipline and early
semantic cutoff materially reduce redundant work; in our tests B is often more
efficient than A.

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
* Or Docker (with `docker compose`) to run without local Prolog installation.
