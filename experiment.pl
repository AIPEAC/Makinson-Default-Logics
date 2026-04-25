%%% experiment.pl
%%% Reproducible Monte Carlo experiment comparing two default-logic
%%% extension-enumeration strategies.
%%%
%%% Strategy A  Permutation-based / Single Scan
%%%   - Randomly permute the n rules; scan once in order.
%%%   - Apply a rule if applicable; skip and never revisit otherwise.
%%%   - One permutation => at most one extension.
%%%   - Repeat with different random permutations until all distinct
%%%     extensions are discovered (coupon-collector problem).
%%%
%%% Strategy B  Fixpoint / Full Rescan
%%%   - Whenever a default fires and adds a new atom, restart scanning
%%%     from rule 1 immediately (deterministic, no backtracking).
%%%   - Repeat until no rule fires => one fixpoint extension.
%%%   - Enumerate all extensions by seeding the fixpoint with each of
%%%     the 2^k possible resolutions of the k conflict pairs.
%%%
%%% See README.md for full description and usage instructions.

:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(library(apply)).

% ============================================================
% Configuration  (edit to adjust the experiment)
% ============================================================

%% n_values(?Ns)
%  List of total rule-counts to sweep over.
n_values([8, 10, 12, 14, 16, 18, 20]).

%% k_for_n(+N, -K)
%  K conflict pairs for a theory of size N.
%  Each pair contributes 2 rules and doubles the number of extensions,
%  so 2^K extensions in total.
%  The divisor 4 keeps roughly a quarter of the rules as conflict rules and
%  the remainder as independent rules.  This gives a moderate number of
%  extensions (2^K) without making K so large that enumeration is impractical
%  within the default max_perms cap.
k_for_n(N, K) :- K is max(2, N // 4).

%% mc_runs(?Runs)
%  Number of independent Strategy-A Monte Carlo trials per n value.
mc_runs(10).

%% max_perms(?Cap)
%  Hard cap on the number of random permutations per Strategy-A trial.
%  If all extensions are found before this limit the trial terminates early.
max_perms(200000).

% ============================================================
% Entry Point
% ============================================================

:- initialization(main, main).

main :-
    format("~`=t~65|~n"),
    format("Default Logic Extension-Enumeration Experiment~n"),
    format("~`=t~65|~n~n"),
    mc_runs(MC), max_perms(MP),
    format("Monte Carlo runs per n (Strategy A) : ~w~n", [MC]),
    format("Max permutations cap per A-trial    : ~w~n~n", [MP]),
    n_values(Ns),
    maplist(run_experiment_for_n, Ns),
    format("~`=t~65|~n"),
    halt.

run_experiment_for_n(N) :-
    k_for_n(N, K),
    NumExts is 1 << K,          % 2^K
    mc_runs(MCRuns),
    max_perms(MaxPerms),
    generate_theory(N, K, Rules),
    format("~`-t~65|~n"),
    format("n=~w  |  conflict_pairs=~w  |  extensions=~w~n",
           [N, K, NumExts]),

    % --- Strategy B : deterministic, systematic ---
    strategy_b_enumerate_all(Rules, K, FoundExtsB, BConstr, BChecks),
    length(FoundExtsB, NumFoundB),
    format("  [B] constructions=~w   total_checks=~w   found=~w/~w~n",
           [BConstr, BChecks, NumFoundB, NumExts]),

    % --- Strategy A : random permutations, MC average ---
    run_mc_strategy_a(Rules, NumExts, MaxPerms, MCRuns,
                      SumPerms, SumChecks, HitCount),
    AvgPerms  is SumPerms  / MCRuns,
    AvgChecks is SumChecks / MCRuns,
    format("  [A] avg_perms=~1f   avg_checks=~1f   cap_hits=~w/~w~n",
           [AvgPerms, AvgChecks, HitCount, MCRuns]),

    % --- Ratio ---
    (BChecks > 0 ->
        Ratio is AvgChecks / BChecks,
        format("  ratio A_checks/B_checks=~2f~n~n", [Ratio])
    ;   nl).

% ============================================================
% Theory Generation
% ============================================================
% Produces K conflict pairs plus (N - 2*K) independent rules.
%
% Conflict pair I:
%   rule([], [neg_I], pos_I)   "pos_I  :  -neg_I / pos_I"
%   rule([], [pos_I], neg_I)   "neg_I  :  -pos_I / neg_I"
%
% Independent rule I:
%   rule([], [], indep_I)      always applicable; always fires once
%
% With this structure the theory has exactly 2^K distinct extensions.

generate_theory(N, K, Rules) :-
    numlist(1, K, PairIds),
    maplist(make_conflict_pair, PairIds, PairsList),
    flatten(PairsList, ConflictRules),
    NIndep is N - K * 2,
    (NIndep > 0 ->
        numlist(1, NIndep, IIds),
        maplist(make_indep_rule, IIds, IndepRules)
    ;   IndepRules = []),
    append(ConflictRules, IndepRules, Rules).

make_conflict_pair(I, [rule([], [Neg], Pos), rule([], [Pos], Neg)]) :-
    atomic_list_concat([pos, I], '_', Pos),
    atomic_list_concat([neg, I], '_', Neg).

make_indep_rule(I, rule([], [], Atom)) :-
    atomic_list_concat([indep, I], '_', Atom).

% ============================================================
% Applicability Check  (one atomic operation)
% ============================================================
% applicable(+Rule, +BeliefSet)
% A rule rule(Pre, Just, _) is applicable in S when:
%   - every atom in Pre is a member of S   (prerequisite check)
%   - no atom in Just is a member of S     (consistency check)

applicable(rule(Pre, Just, _), S) :-
    subset(Pre, S),
    % member/2 iterates over every element of Just (backtracking generator);
    % memberchk/2 does a deterministic set-membership test against S.
    % Together: fail if ANY justification atom is already believed.
    \+ (member(J, Just), memberchk(J, S)).

% ============================================================
% Strategy A : Permutation-based / Single Scan
% ============================================================

%% strategy_a_scan(+Rules, -Extension, -Checks)
%  Scan Rules exactly once in the given order.
%  Apply each rule if applicable; skip it otherwise.
%  The scan is deterministic: cut suppresses Prolog backtracking.

strategy_a_scan(Rules, Extension, Checks) :-
    strategy_a_scan_(Rules, [], 0, ExtUnsorted, Checks),
    msort(ExtUnsorted, Extension).

strategy_a_scan_([], S, C, S, C) :- !.
strategy_a_scan_([R | Rest], S, C0, SF, CF) :-
    C1 is C0 + 1,
    (   applicable(R, S),
        R = rule(_, _, Conc),
        \+ memberchk(Conc, S)
    ->  S1 = [Conc | S]         % rule fires; add conclusion
    ;   S1 = S                  % rule skipped; never revisited
    ), !,
    strategy_a_scan_(Rest, S1, C1, SF, CF).

%% strategy_a_find_all(+Rules, +TargetNum, +MaxPerms,
%%                     -AllExts, -TotalPerms, -TotalChecks, -HitCap)
%  Draw random permutations until TargetNum distinct extensions are
%  found or MaxPerms permutations have been exhausted.
%  HitCap = yes if the cap was reached before finishing.

strategy_a_find_all(Rules, TargetNum, MaxPerms,
                    AllExts, TotalPerms, TotalChecks, HitCap) :-
    strategy_a_loop(Rules, TargetNum, MaxPerms, [], 0, 0,
                    AllExts, TotalPerms, TotalChecks, HitCap).

strategy_a_loop(_, Tgt, _, Found, P, C, Found, P, C, no) :-
    length(Found, L), L >= Tgt, !.
strategy_a_loop(_, _, MaxP, Found, P, C, Found, P, C, yes) :-
    P >= MaxP, !.
strategy_a_loop(Rules, Tgt, MaxP, Found, P0, C0, AF, TP, TC, HC) :-
    random_permutation(Rules, Perm),
    strategy_a_scan(Perm, Ext, ScanC),
    P1 is P0 + 1,
    C1 is C0 + ScanC,
    (memberchk(Ext, Found) -> F1 = Found ; F1 = [Ext | Found]),
    strategy_a_loop(Rules, Tgt, MaxP, F1, P1, C1, AF, TP, TC, HC).

%% run_mc_strategy_a(+Rules, +NumExts, +MaxPerms, +MCRuns,
%%                   -SumPerms, -SumChecks, -TotalHits)
%  Run MCRuns independent trials, each seeded differently.
%  Accumulate total permutations and checks across all trials.

run_mc_strategy_a(Rules, NumExts, MaxPerms, MCRuns,
                  SumPerms, SumChecks, TotHit) :-
    run_mc_(Rules, NumExts, MaxPerms, MCRuns, 1,
            0, 0, 0, SumPerms, SumChecks, TotHit).

run_mc_(_, _, _, 0, _, SP, SC, SH, SP, SC, SH) :- !.
run_mc_(Rules, NumExts, MaxP, Rem, Seed,
        SP0, SC0, SH0, SP, SC, SH) :-
    set_random(seed(Seed)),
    strategy_a_find_all(Rules, NumExts, MaxP, _, Perms, Checks, Hit),
    SP1 is SP0 + Perms,
    SC1 is SC0 + Checks,
    (Hit = yes -> SH1 is SH0 + 1 ; SH1 = SH0),
    Seed1 is Seed + 1,
    Rem1  is Rem  - 1,
    run_mc_(Rules, NumExts, MaxP, Rem1, Seed1, SP1, SC1, SH1, SP, SC, SH).

% ============================================================
% Strategy B : Fixpoint / Full Rescan
% ============================================================

%% strategy_b_fp(+Rules, +InitS, -Extension, -Checks)
%  Deterministic fixpoint computation starting from InitS.
%  Scans All rules in order; when a rule fires (adds a new atom),
%  immediately restart from rule 1 (no Prolog backtracking; cut used).

strategy_b_fp(Rules, InitS, Extension, Checks) :-
    strategy_b_fp_(Rules, Rules, InitS, 0, ExtUnsorted, Checks),
    msort(ExtUnsorted, Extension).

%% strategy_b_fp_(+AllRules, +ToScan, +S, +C0, -SF, -CF)
%  AllRules  : full rule list (used to restart)
%  ToScan    : remaining rules in current pass

strategy_b_fp_(_, [], S, C, S, C) :- !.    % Finished pass without change = fixpoint
strategy_b_fp_(All, [R | Rest], S, C0, SF, CF) :-
    C1 is C0 + 1,
    (   applicable(R, S),
        R = rule(_, _, Conc),
        \+ memberchk(Conc, S)
    ->  % New atom added: restart from rule 1
        strategy_b_fp_(All, All, [Conc | S], C1, SF, CF)
    ;   % Rule not fired: continue scan
        strategy_b_fp_(All, Rest, S, C1, SF, CF)
    ), !.

%% strategy_b_enumerate_all(+Rules, +K,
%%                          -AllExts, -TotalConstr, -TotalChecks)
%  Enumerate all 2^K extensions systematically.
%  For conflict pair I, bit (I-1) of the combo index chooses pos_I (0)
%  or neg_I (1) as the seed atom.  Running one fixpoint per combo
%  and deduplicating with memberchk/2 + msort/2.

strategy_b_enumerate_all(Rules, K, AllExts, TotalConstr, TotalChecks) :-
    NumCombos is 1 << K,
    Last is NumCombos - 1,
    numlist(0, Last, Idxs),
    maplist(idx_to_init(K), Idxs, InitSets),
    run_b_for_all(Rules, InitSets, [], 0, 0,
                  AllExts, TotalConstr, TotalChecks).

run_b_for_all(_, [], Found, C, Ch, Found, C, Ch) :- !.
run_b_for_all(Rules, [Init | Rest], Found, C0, Ch0, AF, TC, TCh) :-
    strategy_b_fp(Rules, Init, Ext, ThisCh),
    C1  is C0  + 1,
    Ch1 is Ch0 + ThisCh,
    (memberchk(Ext, Found) -> F1 = Found ; F1 = [Ext | Found]),
    run_b_for_all(Rules, Rest, F1, C1, Ch1, AF, TC, TCh).

%% idx_to_init(+K, +Idx, -InitSet)
%  Convert a combo index (0 .. 2^K - 1) to an initial belief set.
%  Bit (I-1) = 0 => pos_I, 1 => neg_I.

idx_to_init(K, Idx, InitSet) :-
    numlist(1, K, Ids),
    maplist(bit_to_atom(Idx), Ids, InitSet).

bit_to_atom(Idx, I, Atom) :-
    Bit is (Idx >> (I - 1)) /\ 1,
    (Bit =:= 0
    ->  atomic_list_concat([pos, I], '_', Atom)
    ;   atomic_list_concat([neg, I], '_', Atom)
    ).
