---- MODULE NodeTextfile ----
EXTENDS Naturals, Sequences

CONSTANT SamplesToFire
VARIABLES streak, recent

Init ==
    /\ streak = 0
    /\ recent = [sample \in 1..SamplesToFire |-> FALSE]

ReachableWithError ==
    /\ recent' = Append(Tail(recent), TRUE)
    /\ streak' = IF streak = SamplesToFire THEN streak ELSE streak + 1

Ineligible ==
    /\ recent' = Append(Tail(recent), FALSE)
    /\ streak' = 0

Next == ReachableWithError \/ Ineligible

TypeOK ==
    /\ streak \in 0..SamplesToFire
    /\ recent \in [1..SamplesToFire -> BOOLEAN]

FiresExactlyAfterHold ==
    (streak = SamplesToFire) <=> (\A sample \in 1..SamplesToFire : recent[sample])
====
