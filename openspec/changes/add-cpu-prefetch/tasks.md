## 1. Establish the ceiling before building to it

- [ ] 1.1 Re-run the bandwidth analysis on nemo and celeste as well as breakout;
      the 2.020 bytes / 0.604 data accesses per instruction that motivate this
      are one corpus's numbers
- [ ] 1.2 Measure the **dynamic** instruction mix, not the static one. Every
      figure here weights by instructions written; a hot loop can be 2% of the
      source and 50% of the cycles, and it would re-rank the whole change
- [ ] 1.3 Measure the real distribution of control transfers taken vs not, to
      replace the 50%-of-branches assumption in the flush budget

## 2. The queue, against today's single port

- [ ] 2.1 Four-byte queue with tags, autonomous fill, flush on control transfer
- [ ] 2.2 Confine prefetch to RAM; stop at a peripheral window boundary
- [ ] 2.3 Snoop stores against the queue tags and invalidate on a hit
- [ ] 2.4 Decode from the queue rather than from the memory data bus
- [ ] 2.5 Confirm no IPC regression on one port, and re-measure Fmax — the
      opcode now arrives from a flop, so the critical path should leave the
      memory output

## 3. Conformance for a prefetching core

- [ ] 3.1 Give the harness an access classifier: instruction access vs prefetch
- [ ] 3.2 Apply Tier 2 unchanged to instruction accesses; permit prefetch only
      within the queue's reach in RAM, counted and reported
- [ ] 3.3 Directed test for the store snoop: write to a byte in the queue and
      require the new byte to execute
- [ ] 3.4 Re-run the full 1.51 M sweep, the stall injection and Dormann

## 4. The second port

- [ ] 4.1 Fetch through the memory interface's second port on the dual-port
      backend (**depends on `add-memory-subsystem`**)
- [ ] 4.2 Sixteen-bit fill on the SDRAM backend: one access, two bytes
- [ ] 4.3 Record the cycle table per backend; `docs/cpu-timing-*.json` stops
      being one number and has to name the backend

## 5. Collect the win

- [ ] 5.1 Static and dynamic CPI per backend against the 2.755 baseline
- [ ] 5.2 Fmax and area against the current 48.60 MHz / 1232 LC
- [ ] 5.3 Measured flush penalty against the 1-cycle assumption; if it is 3,
      say so and re-state the expected win
- [ ] 5.4 Recover the implied instruction's cycle now that decode is off the
      memory output, with forwarding or an interlock for the stack hazard —
      whichever measures cheaper
