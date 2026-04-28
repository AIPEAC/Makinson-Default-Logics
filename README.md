# Makinson Default Logics — Extension Enumeration Experiment

Empirically compares three extension-construction schedules for propositional
default theories, implemented in SWI-Prolog.

- [Theory & Mathematical analysis](https://github.com/AIPEAC/Makinson-Default-Logics/blob/8d9d9b6feb22a51bc525050947fbded601146d27/README.md#L12)
- [Run the program yourself](https://github.com/AIPEAC/Makinson-Default-Logics/blob/8d9d9b6feb22a51bc525050947fbded601146d27/README.md#L157)


---

## Theory Model & Background

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

### Metrics Collected

For each strategy and each `n`:

1. `avg_trials`: average number of constructions attempted over `mc_runs`.
2. `avg_checks`: average total applicability checks over `mc_runs`.
3. `cap_hits`: how many runs terminated due to `max_trials` cap.

Ratios versus Strategy 0 are also printed:

1. `A_checks / 0_checks`
2. `B_checks / 0_checks`

---

### Configuration

Edit the top of `experiment.pl`:

| Predicate | Default | Description |
|-----------|---------|-------------|
| `n_values/1` | `[4,6,8]` | List of rule-counts to sweep |
| `k_for_n/2` | `max(2, N // 4)` | Conflict pairs for a theory of size N |
| `mc_runs/1` | `10` | Number of repeated runs used to average each strategy |
| `max_trials/1` | `200000` | Safety cap on constructions per strategy run |


### Experimental Setup

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


### Analysis (mathematical summary)

Let $K$ be the number of conflict pairs and $m=2^K$ the number of extensions.

- Strategy 0 (deterministic Xi sweep): covers $m$ seeds exactly once, so the
  number of constructions is $m$ (or the `max_trials` cap if smaller). If
  $c_R(n)$ is the mean cost of one Reiter fixpoint closure on a theory of size
  $n$, then

$$
T_0(n, K) = 2^K \cdot c_R(n).
$$

  This is exact for the full sweep, up to the cap.

- Strategy A (permutation single-scan, conventional agenda-style): when
  implemented as random permutations the classical coupon-collector model
  applies. If $c_A(n)$ is the mean cost of one permutation-driven construction,
  then the expected total time is

$$
T_A(n, K) = c_A(n) \cdot 2^K \cdot H_{2^K}.
$$

  where $H_m = \sum_{i=1}^m \frac{1}{i}$ is the $m$th harmonic number. Using
  the standard expansion,

$$
T_A(n, K) = c_A(n) \cdot 2^K \cdot (\ln(2^K) + \gamma) + o(2^K),
$$

  so the constant factor $c_A(n)$ is visible in the runtime itself. This is why
  random-resample A needs noticeably more work than an exact sweep.

- Strategy B (FIFO skipped-queue): like A it explores the permutation tree,
  but its FIFO policy plus the semantic tree cutoff reduce repeated scans. If
  $c_B(n)$ is the mean cost of one FIFO construction, then

$$
T_B(n, K) = c_B(n) \cdot 2^K \cdot H_{2^K}.
$$

  The difference from A is the per-construction constant. FIFO avoids the extra
  priority-list maintenance and tends to revisit fewer stale candidates, so in
  this family we measure $c_B(n) < c_A(n)$.

Comparative intuition:

- A (conventional agenda/permutation sampling) is equivalent to many
  production-system/agenda conflict-resolution strategies (see Forgy, OPS5/Rete
  literature) where conflict resolution order matters and can dominate
  performance. Its total runtime is the larger constant $c_A(n)$ multiplied by
  the same coupon-collector factor $2^K H_{2^K}$.
- B gains from queueing discipline and the permutation-tree semantic cutoff;
  it therefore avoids many redundant full scans that A would revisit under
  random sampling. In runtime terms,

$$
T_B(n, K) - T_A(n, K) = (c_B(n) - c_A(n)) \cdot 2^K \cdot H_{2^K},
$$

  and since the measured constant satisfies $c_B(n) < c_A(n)$, the difference
  is negative. That is the mathematical reason B is faster than A in this
  family.

Practical takeaway: if you want exact one-shot coverage of all Xi without
sampling overhead, use Strategy 0 (deterministic enumeration). If you must
explore permutation-induced constructions (A/B), queue discipline and early
semantic cutoff materially reduce redundant work; in our tests B is often more
efficient than A.

---

## Experiment Code & Reproducibility

### Repository Structure

```
.
├── experiment.pl                   # Core SWI-Prolog experiment
├── Dockerfile                      # Docker image (based on swipl:latest)
├── .github/
│   └── workflows/
│       └── experiment.yml          # GitHub Actions workflow
└── README.md
```

### Requirements

* **SWI-Prolog ≥ 8.0** (uses `library(lists)`, `library(random)`,
  `library(apply)`)
* Or **Docker** (with `docker compose`) to run without local Prolog installation.

---
### Running the Experiment

#### Directly with SWI-Prolog

```bash
swipl -s experiment.pl
```

#### With Docker (pull from GHCR)

```bash
sh ./run.sh

# equivalent manual commands:
docker compose pull
docker compose run --rm experiment
```

### Via GitHub Actions

The workflow at `.github/workflows/experiment.yml` runs automatically on every
`push` and prints results to the workflow log.

