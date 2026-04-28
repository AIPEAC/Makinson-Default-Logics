# Complexity Proof: Reiter’s Algorithm with Brute-Force SAT

This proof explicitly calculates the time complexity of Reiter’s algorithm for enumerating extensions of a propositional default theory, substituting a generic SAT oracle with a brute-force truth-table check.

### 1. Cost of a Single Consistency/Entailment Check
Given a set of formulas $S$ (where $|S| \le n+r$) and a formula $\phi$, we decide consistency ($S \not\models \lnot\phi$) or entailment ($S \models \phi$) by enumerating all $2^{a}$ truth assignments over $a$ atoms.

* Evaluating a formula of standard length takes time $\le c$ for some constant $c$.
* One check costs: $c \cdot (|S|+1) \cdot 2^{a} \le c\,(n+r+1)\,2^{a}$.
* Simplifying the bound: 
    $$T_{\text{check}}(n,r,a) = c\,(n+r)\,2^{a}$$

### 2. Overhead of Building Candidate Knowledge Bases
For each of the $2^{r}$ subsets $D \subseteq \Delta$, we copy $n$ formulas from $\Phi$ and the consequents of the defaults in $D$. The total formula copy operations (assuming unit cost) are:

$$\sum_{D} (n+|D|) = 2^{r}n + \sum_{k=0}^{r}\binom{r}{k}k = 2^{r}n + r2^{r-1} = 2^{r}\Bigl(n+\frac{r}{2}\Bigr)$$

### 3. Number of Checks
The algorithm iterates through all $2^r$ subsets. For each subset, it checks defaults $\delta_1, \dots, \delta_r$ in order. A check consists of prerequisite entailment and/or justification consistency.

| Case | Checks per Subset | Total Checks |
| :--- | :--- | :--- |
| **Best Case** | 1 (Failure on $\delta_1$) | $2^{r}$ |
| **Average Case** | $\approx r$ (Half defaults tested, 2 checks each) | $r2^{r}$ |
| **Worst Case** | $2r$ (Every default tested, 2 checks each) | $2r2^{r}$ |

### 4. Total Time Complexity
The total time is the sum of the overhead and the (number of checks $\times$ cost per check).

#### Best Case
$$T_{\text{best}}(r,n,a) = 2^{r}\Bigl(n+\frac{r}{2}\Bigr) + 2^{r} \cdot c\,(n+r)\,2^{a}$$

#### Average Case
$$T_{\text{avg}}(r,n,a) = 2^{r}\Bigl(n+\frac{r}{2}\Bigr) + r2^{r} \cdot c\,(n+r)\,2^{a}$$

#### Worst Case
$$T_{\text{worst}}(r,n,a) = 2^{r}\Bigl(n+\frac{r}{2}\Bigr) + 2r2^{r} \cdot c\,(n+r)\,2^{a}$$

---

### Final Bound (Worst Case)
Grouping the terms to show the exponential growth relative to the signature size $a$ and the number of defaults $r$:

$$\boxed{T_{\text{worst}}(r,n,a) = 2^{r}\left[n + \frac{r}{2} + 2c \cdot r(n+r) \cdot 2^{a}\right]}$$