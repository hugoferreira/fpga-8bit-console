# Working in this repo

**Two agents are working in this checkout at once**, on the same branch, with
uncommitted work from both: one on the NEMO port (`src/nemo/`), one on the
Celeste port (`src/celeste/`).

**Read [`docs/agent-coordination.md`](docs/agent-coordination.md) before
editing anything you did not write.** It holds:

- which paths each agent owns, and which four files are shared
  (`tools/isa_metrics.py`, `docs/corpora.md`, `docs/hardware-gaps.md`,
  `Makefile`)
- the append-don't-rewrite protocol for those four
- open requests in both directions, including two that need the nemo agent:
  a one-pixel framebuffer offset in `sim/console.cpp`, and a measurement
  artifact that makes `make metrics` print the opposite of the frame-pressure
  result recorded in `docs/corpora.md`

Delete this section once both changes are archived.
