%%% experiment.pl
%%% Reproducible Monte Carlo experiment comparing two default-logic
%%% extension-enumeration strategies.
%%%
%%% Strategy 0  Reiter baseline (random Xi)
%%%   - Repeatedly draw a random Xi seed (conflict resolution choice).
%%%   - Run deterministic Reiter-style fixpoint closure from that Xi.
%%%   - Keep sampling until all extensions are discovered (or cap).
%%%
%%% Strategy A  Makinson with priority queue for skipped rules
%%%   - Draw a random rule sequence.
%%%   - If a rule is skipped (trigger not yet enabled), store it in a
%%%     priority queue where older skipped rules have higher priority.
%%%   - Whenever IN updates, revisit skipped rules first (oldest first).
%%%
%%% Strategy B  Makinson with FIFO queue for skipped rules
%%%   - Draw a random rule sequence.
%%%   - If a rule is skipped, move it to the tail of the queue.
%%%   - Terminate on a full no-progress round (no rule fired while
%%%     visiting each queued rule once), preventing infinite cycling.
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
%  Number of independent Monte Carlo trials per strategy and per n value.
mc_runs(10).

%% max_trials(?Cap)
%  Hard cap on randomized construction attempts per strategy trial.
%  A and B stop earlier only when their permutation process tree is exhausted.
max_trials(200000).

% ============================================================
% Entry Point
% ============================================================

:- initialization(main, main).

main :-
    format("~`=t~65|~n"),
    format("Default Logic Extension-Enumeration Experiment~n"),
    format("~`=t~65|~n~n"),
    mc_runs(MC), max_trials(MT),
    format("Monte Carlo runs per n (each strategy) : ~w~n", [MC]),
    format("Max randomized constructions per trial : ~w~n~n", [MT]),
    n_values(Ns),
    maplist(run_experiment_for_n, Ns),
    format("~`=t~65|~n"),
    halt.

run_experiment_for_n(N) :-
    k_for_n(N, K),
    NumExts is 1 << K,          % 2^K
    mc_runs(MCRuns),
    max_trials(MaxTrials),
    generate_theory(N, K, Rules),
    format("~`-t~65|~n"),
    format("n=~w  |  conflict_pairs=~w  |  extensions=~w~n",
           [N, K, NumExts]),

    % --- Strategy 0 : Reiter baseline (random Xi) ---
    run_mc_strategy_0(Rules, K, NumExts, MaxTrials, MCRuns,
             SumTr0, SumChk0, Hit0),
    AvgTr0  is SumTr0  / MCRuns,
    AvgChk0 is SumChk0 / MCRuns,
    format("  [0] avg_trials=~1f   avg_checks=~1f   cap_hits=~w/~w~n",
        [AvgTr0, AvgChk0, Hit0, MCRuns]),

    % --- Strategy A : Makinson priority re-check of skipped rules ---
    run_mc_strategy_a(Rules, MaxTrials, MCRuns,
             SumTrA, SumChkA, HitA),
    AvgTrA  is SumTrA  / MCRuns,
    AvgChkA is SumChkA / MCRuns,
    format("  [A] avg_trials=~1f   avg_checks=~1f   cap_hits=~w/~w~n",
        [AvgTrA, AvgChkA, HitA, MCRuns]),

    % --- Strategy B : Makinson FIFO queue ---
    run_mc_strategy_b(Rules, MaxTrials, MCRuns,
             SumTrB, SumChkB, HitB),
    AvgTrB  is SumTrB  / MCRuns,
    AvgChkB is SumChkB / MCRuns,
    format("  [B] avg_trials=~1f   avg_checks=~1f   cap_hits=~w/~w~n",
        [AvgTrB, AvgChkB, HitB, MCRuns]),

    (AvgChk0 > 0 ->
     RatioA0 is AvgChkA / AvgChk0,
     RatioB0 is AvgChkB / AvgChk0,
     format("  ratio A_checks/0_checks=~2f   B_checks/0_checks=~2f~n~n",
         [RatioA0, RatioB0])
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
% Strategy 0 : Reiter baseline with random Xi
% ============================================================

%% strategy_0_reiter_once(+Rules, +K, -Extension, -Checks)
%  Randomly sample one Xi seed, then run Reiter fixpoint closure.

strategy_0_reiter_once(Rules, K, Extension, Checks) :-
    NumExts is 1 << K,
    MaxIdx is NumExts - 1,
    random_between(0, MaxIdx, XiIdx),
    idx_to_init(K, XiIdx, InitS),
    reiter_fixpoint(Rules, InitS, Extension, Checks).

%% reiter_fixpoint(+Rules, +InitS, -Extension, -Checks)
%  Reiter-style deterministic closure: full rescan with restart at rule 1
%  whenever IN grows.

reiter_fixpoint(Rules, InitS, Extension, Checks) :-
    reiter_fixpoint_(Rules, Rules, InitS, 0, ExtUnsorted, Checks),
    msort(ExtUnsorted, Extension).

reiter_fixpoint_(_, [], S, C, S, C) :- !.
reiter_fixpoint_(All, [R | Rest], S, C0, SF, CF) :-
    C1 is C0 + 1,
    (   applicable(R, S),
        R = rule(_, _, Conc),
        \+ memberchk(Conc, S)
    ->  reiter_fixpoint_(All, All, [Conc | S], C1, SF, CF)
    ;   reiter_fixpoint_(All, Rest, S, C1, SF, CF)
    ), !.

%% strategy_0_find_all(+Rules, +K, +TargetNum, +MaxTrials,
%%                     -AllExts, -Trials, -Checks, -HitCap)

strategy_0_find_all(Rules, K, TargetNum, MaxTrials,
                    AllExts, Trials, Checks, HitCap) :-
    strategy_0_loop(Rules, K, TargetNum, MaxTrials, [], 0, 0,
                    AllExts, Trials, Checks, HitCap).

strategy_0_loop(_, _, Tgt, _, Found, T, C, Found, T, C, no) :-
    length(Found, L), L >= Tgt, !.
strategy_0_loop(_, _, _, MaxT, Found, T, C, Found, T, C, yes) :-
    T >= MaxT, !.
strategy_0_loop(Rules, K, Tgt, MaxT, Found, T0, C0, AF, TT, TC, HC) :-
    strategy_0_reiter_once(Rules, K, Ext, ThisC),
    T1 is T0 + 1,
    C1 is C0 + ThisC,
    (memberchk(Ext, Found) -> F1 = Found ; F1 = [Ext | Found]),
    strategy_0_loop(Rules, K, Tgt, MaxT, F1, T1, C1, AF, TT, TC, HC).

run_mc_strategy_0(Rules, K, NumExts, MaxTrials, MCRuns,
                  SumTrials, SumChecks, TotHit) :-
    run_mc_strategy_0_(Rules, K, NumExts, MaxTrials, MCRuns, 1,
                       0, 0, 0, SumTrials, SumChecks, TotHit).

run_mc_strategy_0_(_, _, _, _, 0, _, ST, SC, SH, ST, SC, SH) :- !.
run_mc_strategy_0_(Rules, K, NumExts, MaxT, Rem, Seed,
                   ST0, SC0, SH0, ST, SC, SH) :-
    set_random(seed(Seed)),
    strategy_0_find_all(Rules, K, NumExts, MaxT, _, Trials, Checks, Hit),
    ST1 is ST0 + Trials,
    SC1 is SC0 + Checks,
    (Hit = yes -> SH1 is SH0 + 1 ; SH1 = SH0),
    Seed1 is Seed + 1,
    Rem1  is Rem  - 1,
    run_mc_strategy_0_(Rules, K, NumExts, MaxT, Rem1, Seed1,
                       ST1, SC1, SH1, ST, SC, SH).

% ============================================================
% Process tree for unique initial rule sequences (A/B)
% ============================================================

%% pt_empty(-Tree)
%  Tree node representation: pt(LeafSeen, Exhausted, Children)
%  - LeafSeen  : whether this exact prefix-as-full-sequence was visited
%  - Exhausted : whether this subtree has no unseen branches left
%  - Children  : list of child(Symbol, Subtree)

pt_empty(pt(false, false, [])).

%% pt_is_exhausted(+Tree)

pt_is_exhausted(pt(_, Exhausted, _)) :-
    Exhausted == true.

%% pt_child_get(+Children, +Symbol, -Subtree)
%  Missing child means unseen subtree.

pt_child_get(Children, Symbol, Subtree) :-
    (member(child(Symbol, Found), Children) ->
        Subtree = Found
    ;
        pt_empty(Subtree)
    ).

%% pt_child_put(+Children0, +Symbol, +Subtree, -Children1)

pt_child_put(Children0, Symbol, Subtree, Children1) :-
    (select(child(Symbol, _), Children0, Rest) ->
        Children1 = [child(Symbol, Subtree) | Rest]
    ;
        Children1 = [child(Symbol, Subtree) | Children0]
    ).

%% pt_all_children_exhausted(+Remaining, +Children)
%  True when every next-step symbol already has an exhausted subtree.

pt_all_children_exhausted([], _).
pt_all_children_exhausted([Sym | Rest], Children) :-
    member(child(Sym, Sub), Children),
    pt_is_exhausted(Sub),
    pt_all_children_exhausted(Rest, Children).

%% pt_compute_exhausted(+LeafSeen, +Children, +Remaining, -Exhausted)

pt_compute_exhausted(LeafSeen, _Children, [], Exhausted) :-
    (LeafSeen == true -> Exhausted = true ; Exhausted = false).
pt_compute_exhausted(_LeafSeen, Children, Remaining, Exhausted) :-
    Remaining \= [],
    (pt_all_children_exhausted(Remaining, Children) ->
        Exhausted = true
    ;
        Exhausted = false
    ).

%% pt_available_symbols(+Remaining, +Children, -Candidates)
%  Candidates are symbols whose branch still has unseen leaves.

pt_available_symbols([], _Children, []).
pt_available_symbols([Sym | Rest], Children, Candidates) :-
    (member(child(Sym, Sub), Children), pt_is_exhausted(Sub) ->
        pt_available_symbols(Rest, Children, Candidates)
    ;
        Candidates = [Sym | Tail],
        pt_available_symbols(Rest, Children, Tail)
    ).

%% pt_draw_unique_permutation(+Rules, +Tree0, -Tree1, -Perm, -Status)
%  Draws one unseen permutation by descending a random, non-exhausted branch.
%  Status=ok if a fresh leaf was reached, exhausted if no branch remains.

pt_draw_unique_permutation(Rules, Tree0, Tree1, Perm, Status) :-
    pt_draw_unique_(Tree0, Rules, Tree1, Perm, Status).

pt_draw_unique_(pt(LeafSeen0, Exhausted0, Children0), Remaining,
                pt(LeafSeen1, Exhausted1, Children1), Perm, Status) :-
    (Exhausted0 == true ->
        LeafSeen1 = LeafSeen0,
        Exhausted1 = Exhausted0,
        Children1 = Children0,
        Perm = [],
        Status = exhausted
    ;
        (Remaining = [] ->
            LeafSeen1 = true,
            Exhausted1 = true,
            Children1 = Children0,
            Perm = [],
            Status = ok
        ;
            pt_available_symbols(Remaining, Children0, Candidates),
            (Candidates = [] ->
                LeafSeen1 = LeafSeen0,
                Exhausted1 = true,
                Children1 = Children0,
                Perm = [],
                Status = exhausted
            ;
                random_member(Sym, Candidates),
                select(Sym, Remaining, RestRemaining),
                pt_child_get(Children0, Sym, Child0),
                pt_draw_unique_(Child0, RestRemaining, Child1, Suffix, ok),
                pt_child_put(Children0, Sym, Child1, Children1),
                pt_compute_exhausted(LeafSeen0, Children1, Remaining, Exhausted1),
                LeafSeen1 = LeafSeen0,
                Perm = [Sym | Suffix],
                Status = ok
            )
        )
    ).

% ============================================================
% Strategy A : Makinson with priority queue for skipped rules
% ============================================================

%% strategy_a_makinson_once(+PermutedRules, -Extension, -Checks)
%  Priority behavior for skipped rules:
%  - skipped rules are stored in insertion order (oldest first)
%  - after any IN update, skipped rules are revisited before newer rules

strategy_a_makinson_once(PermRules, Extension, Checks) :-
    strategy_a_makinson_loop(PermRules, [], [], false, 0, ExtUnsorted, Checks),
    msort(ExtUnsorted, Extension).

%% strategy_a_makinson_loop(+Queue, +Skipped, +S, +Progress, +C0, -SF, -CF)
%  Queue    : current processing queue
%  Skipped  : skipped rules waiting in priority order (oldest at head)
%  Progress : true if IN changed in the current queue cycle

strategy_a_makinson_loop([], [], S, _, C, S, C) :- !.
strategy_a_makinson_loop([], Skipped, S, true, C0, SF, CF) :-
    % IN changed in this cycle: give skipped rules another chance.
    !,
    strategy_a_makinson_loop(Skipped, [], S, false, C0, SF, CF).
strategy_a_makinson_loop([], _Skipped, S, false, C, S, C) :- !.
strategy_a_makinson_loop([R | Rest], Skipped, S, Progress0, C0, SF, CF) :-
    C1 is C0 + 1,
    (   applicable(R, S),
        R = rule(_, _, Conc),
        \+ memberchk(Conc, S)
    ->  % IN update: revisit skipped rules immediately (oldest first).
        append(Skipped, Rest, Queue1),
        strategy_a_makinson_loop(Queue1, [], [Conc | S], true, C1, SF, CF)
    ;   % Rule did not fire now: keep age order in skipped priority queue.
        append(Skipped, [R], Skipped1),
        strategy_a_makinson_loop(Rest, Skipped1, S, Progress0, C1, SF, CF)
    ), !.

strategy_a_find_all(Rules, MaxTrials, Trials, Checks, HitCap) :-
    pt_empty(UsedSeqTree),
    strategy_a_loop(Rules, MaxTrials, 0, 0, UsedSeqTree,
                    Trials, Checks, HitCap).

strategy_a_loop(_, MaxT, T, C, _Used, T, C, yes) :-
    T >= MaxT, !.
strategy_a_loop(Rules, MaxT, T0, C0, Used0, TT, TC, HC) :-
    pt_draw_unique_permutation(Rules, Used0, Used1, Perm, DrawStatus),
    (DrawStatus = exhausted ->
        TT = T0,
        TC = C0,
        HC = no
    ;
        strategy_a_makinson_once(Perm, _Ext, ThisC),
        T1 is T0 + 1,
        C1 is C0 + ThisC,
        strategy_a_loop(Rules, MaxT, T1, C1, Used1, TT, TC, HC)
    ).

run_mc_strategy_a(Rules, MaxTrials, MCRuns,
                  SumTrials, SumChecks, TotHit) :-
    run_mc_strategy_a_(Rules, MaxTrials, MCRuns, 1,
                       0, 0, 0, SumTrials, SumChecks, TotHit).

run_mc_strategy_a_(_, _, 0, _, ST, SC, SH, ST, SC, SH) :- !.
run_mc_strategy_a_(Rules, MaxT, Rem, Seed,
                   ST0, SC0, SH0, ST, SC, SH) :-
    set_random(seed(Seed)),
    strategy_a_find_all(Rules, MaxT, Trials, Checks, Hit),
    ST1 is ST0 + Trials,
    SC1 is SC0 + Checks,
    (Hit = yes -> SH1 is SH0 + 1 ; SH1 = SH0),
    Seed1 is Seed + 1,
    Rem1  is Rem  - 1,
    run_mc_strategy_a_(Rules, MaxT, Rem1, Seed1,
                       ST1, SC1, SH1, ST, SC, SH).

% ============================================================
% Strategy B : Makinson with FIFO queue for skipped rules
% ============================================================

%% strategy_b_makinson_once(+PermutedRules, -Extension, -Checks)
%  FIFO behavior for skipped rules:
%  - skipped rule goes to tail
%  - full no-progress round implies closure (cannot get stuck)

strategy_b_makinson_once(PermRules, Extension, Checks) :-
    strategy_b_makinson_loop(PermRules, [], 0, 0, ExtUnsorted, Checks),
    msort(ExtUnsorted, Extension).

%% strategy_b_makinson_loop(+Queue, +S, +NoFire, +C0, -SF, -CF)
%  NoFire counts consecutive processed queue elements with no IN update.
%  If NoFire reaches queue length, a full no-progress round is complete.

strategy_b_makinson_loop([], S, _, C, S, C) :- !.
strategy_b_makinson_loop([R | Rest], S, NoFire0, C0, SF, CF) :-
    C1 is C0 + 1,
    (   applicable(R, S),
        R = rule(_, _, Conc),
        \+ memberchk(Conc, S)
    ->  % Rule fired: IN changed, so reset no-progress counter.
        strategy_b_makinson_loop(Rest, [Conc | S], 0, C1, SF, CF)
    ;   % Rule did not fire now: move it to queue tail.
        append(Rest, [R], Queue1),
        NoFire1 is NoFire0 + 1,
        length(Queue1, QSize),
        (NoFire1 >= QSize
        ->  % One full round without any fire => closed.
            SF = S,
            CF = C1
        ;   strategy_b_makinson_loop(Queue1, S, NoFire1, C1, SF, CF)
        )
    ), !.

strategy_b_find_all(Rules, MaxTrials, Trials, Checks, HitCap) :-
    pt_empty(UsedSeqTree),
    strategy_b_loop(Rules, MaxTrials, 0, 0, UsedSeqTree,
                    Trials, Checks, HitCap).

strategy_b_loop(_, MaxT, T, C, _Used, T, C, yes) :-
    T >= MaxT, !.
strategy_b_loop(Rules, MaxT, T0, C0, Used0, TT, TC, HC) :-
    pt_draw_unique_permutation(Rules, Used0, Used1, Perm, DrawStatus),
    (DrawStatus = exhausted ->
        TT = T0,
        TC = C0,
        HC = no
    ;
        strategy_b_makinson_once(Perm, _Ext, ThisC),
        T1 is T0 + 1,
        C1 is C0 + ThisC,
        strategy_b_loop(Rules, MaxT, T1, C1, Used1, TT, TC, HC)
    ).

run_mc_strategy_b(Rules, MaxTrials, MCRuns,
                  SumTrials, SumChecks, TotHit) :-
    run_mc_strategy_b_(Rules, MaxTrials, MCRuns, 1,
                       0, 0, 0, SumTrials, SumChecks, TotHit).

run_mc_strategy_b_(_, _, 0, _, ST, SC, SH, ST, SC, SH) :- !.
run_mc_strategy_b_(Rules, MaxT, Rem, Seed,
                   ST0, SC0, SH0, ST, SC, SH) :-
    set_random(seed(Seed)),
    strategy_b_find_all(Rules, MaxT, Trials, Checks, Hit),
    ST1 is ST0 + Trials,
    SC1 is SC0 + Checks,
    (Hit = yes -> SH1 is SH0 + 1 ; SH1 = SH0),
    Seed1 is Seed + 1,
    Rem1  is Rem  - 1,
    run_mc_strategy_b_(Rules, MaxT, Rem1, Seed1,
                       ST1, SC1, SH1, ST, SC, SH).

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
