## ADDED Requirements

### Requirement: Frame-Budget Classification Of Corpora

The corpus registry SHALL record for every corpus whether its code is written
against a per-frame time budget. Gate reports SHALL group plumbing ratios by that
classification, and SHALL NOT compare a frame-bound corpus's ratio directly against
a non-frame-bound one. The corpus set SHALL include at least one non-frame-bound
member, so that plumbing attributable to the instruction set can be distinguished
from plumbing attributable to hand-optimisation.

#### Scenario: Ratios are grouped, not pooled across classes

- **WHEN** `make metrics` reports plumbing ratios for a corpus set containing both
  classes
- **THEN** the ratios are grouped by frame-budget classification, and each corpus is
  compared against its own baseline rather than against a corpus of the other class

#### Scenario: Corpus set lacks a non-frame-bound member

- **WHEN** every registered corpus is frame-bound
- **THEN** the report states that plumbing attributable to the instruction set
  cannot be separated from hand-optimisation

#### Scenario: Classification is recorded per corpus

- **WHEN** a corpus is registered
- **THEN** its entry states whether it is frame-bound, and the metrics output carries
  that flag alongside every ratio derived from it

### Requirement: Corpus Gate Applicability

The corpus registry SHALL state which gates each corpus can and cannot inform. A
gate that a corpus structurally cannot measure SHALL be reported as inapplicable for
that corpus rather than omitted or reported as zero.

#### Scenario: Frame-work gate on a corpus with no frame work

- **WHEN** the frame-work cycle gate is evaluated for a corpus that idles waiting for
  input rather than doing per-frame work
- **THEN** it is reported as inapplicable for that corpus, with the reason, and does
  not contribute to the combined verdict

#### Scenario: Inapplicable is distinguished from unmeasured

- **WHEN** a gate result is absent for a corpus
- **THEN** the report distinguishes "structurally inapplicable" from "not yet
  measured", because the two require different responses

### Requirement: Hardware Gaps Surfaced By Porting

When a corpus requires a console capability that does not exist, the port SHALL
record the gap in `docs/hardware-gaps.md` — stating what the original program does,
what the port does instead, and what implementing it would cost — rather than
degrading the ported behaviour silently. A corpus SHALL NOT be registered while a
capability it needed is worked around without an entry.

#### Scenario: Missing capability is recorded

- **WHEN** a port cannot reproduce a behaviour of the original because the console
  lacks the hardware
- **THEN** `docs/hardware-gaps.md` gains an entry naming the capability, the
  original's behaviour, the port's substitute, and an estimate of what a fix requires

#### Scenario: Silent workaround blocks registration

- **WHEN** a corpus is submitted for registration having quietly dropped a behaviour
  that the hardware could not support
- **THEN** registration fails until the gap is recorded

#### Scenario: Gap entry informs a downstream proposal

- **WHEN** a recorded gap is later addressed by its own change
- **THEN** that change can cite the corpus and the measured demand as its evidence,
  rather than arguing from first principles
