## 1. Implementation

- [x] 1.1 psg.sv: phase-accumulator tone gen, PICO-8-native note sequencer, SFX RAM with auto-inc upload port
- [x] 1.2 Integration: $4100 arbiter window, chip wiring, audio out through both tops, SDL 44.1kHz resampling in the runner
- [x] 1.3 Standalone TB: uploaded the cart's lose-ball sweep, verified volume scaling and falling pitch (fixed a 10-bit mixer truncation found by the test)
- [x] 1.4 Game: cart SFX extracted from ROM, uploaded at boot, wired to wall/paddle/brick/shatter/lose/serve/chain events
