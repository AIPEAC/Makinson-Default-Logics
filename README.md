# Makinson Default Logics — Extension Enumeration Experiment

Empirically compares three extension-construction schedules for propositional
default theories, implemented in SWI-Prolog.

- [Theory & Background](https://github.com/AIPEAC/Makinson-Default-Logics/blob/8d9d9b6feb22a51bc525050947fbded601146d27/README.md#L12)
- [Mathematical Analysis](https://github.com/AIPEAC/Makinson-Default-Logics/blob/8d9d9b6feb22a51bc525050947fbded601146d27/README.md#L85)
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

- Given: 
  $$a = num(atoms)$$
  $$r = |\Delta|$$
  $$n = |\Phi|$$
- Unknowns: 
$$num(extensions)$$


**Strategy 0 (deterministic Xi sweep, Reiter):** 

- Average cost:
$$T_0(r,n,a) = 2^{r}\Bigl(n+\frac{r}{2}\Bigr) + r2^{r} \cdot c\,(n+r)\,2^{a}$$
- given $(a \leq n) \land (r \in O(n))$
$$T_0(r,n,a) \subset O(r\cdot n\cdot 2^a\cdot 2^r)\subseteq O(n^2\cdot 2^{O(n)})$$
- Full proof in [reiter-time-analysis.md](./maths/reiter-time-analysis.md).

**Strategy A (permutation single-scan, Makinson agenda-style):**

A and B explore the $r!$ permutation space. To discover all $m$ distinct
extensions by random sampling, the coupon-collector model says we need
$m \cdot H_m$ expected random permutation draws. For each permutation, process
the $r$ rules in order: check applicability ($O(1)$ per rule) and handle skipped
rules using a **priority queue** (manage revisits with $O(\log r)$ per operation).
One permutation construction is $O(r \log r)$ due to queue overhead. Total cost:

$$
T_A = r \log r \cdot m \cdot H_m.
$$

**Strategy B (FIFO skipped-queue, Makinson FIFO):**

Like A, also pays the coupon-collector cost $m \cdot H_m$ to explore permutations.
But uses a **FIFO queue** instead of priority queue: O(1) per operation instead of
$O(\log r)$. Semantic tree cutoff prunes equivalent permutation prefixes, further
reducing redundant exploration. One permutation construction is $O(r)$ (linear
scan with simple queue). Total cost:

$$
T_B = r \cdot m \cdot H_m.
$$

**Comparison:**

$$
T_A - T_B = r \log r \cdot m \cdot H_m - r \cdot m \cdot H_m = (r \log r - r) \cdot m \cdot H_m = r(\log r - 1) \cdot m \cdot H_m.
$$

For $r > 2$, we have $\log r > 1$, so $T_A > T_B$: **B is faster than A by a factor
of $\log r$**. Both pay the unavoidable coupon-collector overhead $m \cdot H_m$
(inherent to random sampling from $r!$), but B avoids the priority queue management
cost that A incurs.

**Summary:**

- **Strategy 0:** $T_0 = m \cdot r \cdot a$ — deterministic, exact, no sampling overhead.
- **Strategy A:** $T_A = r \log r \cdot m \cdot H_m$ — random permutation sampling with priority queue.
- **Strategy B:** $T_B = r \cdot m \cdot H_m$ — random permutation sampling with FIFO queue, $\log r$ times faster than A.

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

