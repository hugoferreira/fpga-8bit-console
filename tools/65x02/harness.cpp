// SingleStepTests/65x02 conformance harness.
//
// Drives rtl/cpu6502_sst.sv (a shim over whichever core is selected) against
// the packed fixture written by tools/65x02/pack.py, one case per instruction.
//
//   make test-65x02                 fast subset, the 151 documented opcodes
//   make test-65x02 CASES=0         the full sweep
//   make test-65x02 OPCODE=91       one opcode
//
// Three tiers, per openspec/changes/refactor-cpu-core/design.md:
//
//   1  architectural state after the instruction: PC, S, A, X, Y, masked P,
//      and every address the case lists in `final.ram`.            GATE
//   2  access footprint: no address touched that the case does not list in
//      either ram list. On this console those windows are peripherals, so a
//      stray read is an event, not a wasted cycle.                 GATE
//   3  the full cycle array, in order. Diagnostic only - we intend to
//      diverge from NMOS timing - and it never affects the exit code.
//
// == Setting up a case ==
//
// The suite gives initial PC/S/A/X/Y/P, which a 6502 has no bus-level way to
// load. Rather than reach into the core (which would only work on a core built
// to allow it, and not on Arlet at all), the harness assembles a 16-byte
// preamble into a scratch window of the case's own memory:
//
//      LDX #s / TXS / LDA #p / PHA / LDA #a / LDX #x / LDY #y / PLP / JMP pc
//
// PLP is last, so nothing after it disturbs a flag; PHA/PLP net the stack
// pointer back to `s`; and JMP is flag-neutral. The window is placed to avoid
// every address the case names, and outside page 1 so the reset sequence's
// stack traffic cannot land on it. The case's initial RAM is re-applied at the
// instant the case starts, which undoes the one byte PHA touched and the reset
// vector the harness borrowed.
//
// The cost is ~25 cycles of setup per case, which the simulation does not
// notice. The benefit is that this file works unchanged on any 6502 core.
//
// == Knowing when the instruction ended ==
//
// `o_decode` from the shim is high during the cycle in which a fetched opcode
// is decoded. The *second* such cycle after a case starts belongs to the NEXT
// instruction, so:
//
//   - the case's cycles are everything up to but excluding the cycle before it
//     (that cycle is the next opcode's fetch, which the suite does not count),
//   - `final.pc` is the address of that excluded fetch,
//   - the architectural state is final at the END of the decode cycle, because
//     that is where the Arlet core retires the previous instruction's register
//     and flag writes. So the harness clocks one further edge, with writes
//     suppressed, before sampling.
//
// Hugo Sereno, <bytter@gmail.com>

#include "Vcpu6502_sst.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>

// ---------------------------------------------------------------- fixture --

static const char FIX_MAGIC[8] = {'6', '5', 'X', '0', '2', 'F', 'X', '\0'};
static const int  N_OPCODES    = 256;
static const int  HEADER_SIZE  = 64;
static const int  DIRENT_SIZE  = 12;

struct RamEntry { uint16_t addr; uint8_t val; };
struct CycleRec { uint16_t addr; uint8_t val; uint8_t write; };

struct State {
  uint16_t pc; uint8_t s, a, x, y, p;
};

struct Case {
  State initial, final_;
  const uint8_t *ram_i;  uint8_t n_ram_i;
  const uint8_t *ram_f;  uint8_t n_ram_f;
  const uint8_t *cyc;    uint8_t n_cyc;
};

static inline uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline RamEntry ram_at(const uint8_t *base, int i) {
  const uint8_t *p = base + i * 3;
  return RamEntry{rd16(p), p[2]};
}
static inline CycleRec cyc_at(const uint8_t *base, int i) {
  const uint8_t *p = base + i * 4;
  return CycleRec{rd16(p), p[2], p[3]};
}

struct Fixture {
  const uint8_t *base = nullptr;
  size_t size = 0;
  uint32_t count[N_OPCODES];
  uint64_t offset[N_OPCODES];
  std::string commit;
  uint64_t total = 0;

  bool open(const char *path) {
    int fd = ::open(path, O_RDONLY);
    if (fd < 0) { perror(path); return false; }
    struct stat st;
    if (fstat(fd, &st) != 0) { perror(path); ::close(fd); return false; }
    size = (size_t)st.st_size;
    void *m = mmap(nullptr, size, PROT_READ, MAP_PRIVATE, fd, 0);
    ::close(fd);
    if (m == MAP_FAILED) { perror("mmap"); return false; }
    base = (const uint8_t *)m;
    if (size < HEADER_SIZE + N_OPCODES * DIRENT_SIZE ||
        memcmp(base, FIX_MAGIC, 8) != 0) {
      fprintf(stderr, "%s: not a 65x02 fixture\n", path);
      return false;
    }
    commit.assign((const char *)base + 16,
                  strnlen((const char *)base + 16, 41));
    const uint8_t *dir = base + HEADER_SIZE;
    for (int i = 0; i < N_OPCODES; i++) {
      memcpy(&count[i],  dir + i * DIRENT_SIZE,     4);
      memcpy(&offset[i], dir + i * DIRENT_SIZE + 4, 8);
      total += count[i];
    }
    return true;
  }

  // Decode one case in place; returns the cursor past it.
  const uint8_t *decode(const uint8_t *p, Case &c) const {
    c.initial = State{rd16(p), p[2], p[3], p[4], p[5], p[6]}; p += 7;
    c.final_  = State{rd16(p), p[2], p[3], p[4], p[5], p[6]}; p += 7;
    c.n_ram_i = *p++; c.ram_i = p; p += c.n_ram_i * 3;
    c.n_ram_f = *p++; c.ram_f = p; p += c.n_ram_f * 3;
    c.n_cyc   = *p++; c.cyc   = p; p += c.n_cyc * 4;
    return p;
  }
};

// ------------------------------------------------------------ flag masking --
//
// Only documented flag results are contractual. Every bit suppressed here is
// counted, so an exclusion that starts absorbing real failures shows up as a
// rising number rather than as silence.

enum MaskRuleId {
  MASK_PBITS45 = 0,
  MASK_DECIMAL_NV = 1,
  MASK_JMP_IND_WRAP = 2,
  N_MASK_RULES = 3
};

static const char *MASK_REASON[N_MASK_RULES] = {
  "P bits 4-5 have no architectural meaning outside a pushed P, and a pushed "
  "P is compared as a RAM byte anyway",
  "N and V after ADC/SBC with D=1 are undocumented on NMOS; the corpus "
  "consumes only C and the result bytes from its BCD chains",
  "JMP ($xxFF): NMOS fetches the high byte from $xx00 instead of crossing the "
  "page. A documented NMOS bug, not implemented here - so the case is checked "
  "against the crossed-page result instead of skipped",
};

static bool is_adc_sbc(uint8_t op) {
  static const uint8_t ops[] = {0x69, 0x65, 0x75, 0x6D, 0x7D, 0x79, 0x61, 0x71,
                                0xE9, 0xE5, 0xF5, 0xED, 0xFD, 0xF9, 0xE1, 0xF1};
  for (uint8_t o : ops) if (o == op) return true;
  return false;
}

// -------------------------------------------------------------- the driver --

struct Opts {
  const char *fixture  = nullptr;
  const char *opcodes  = "tools/65x02/opcodes.txt";
  long cases           = 100;    // 0 = all
  int  opcode_only     = -1;
  bool all_opcodes     = false;
  bool tier3           = false;
  int  max_report      = 8;
  bool verilog_stdout  = false;
  long max_cycles      = 200;
  bool trace           = false;
  long stall           = 0;      // 0 off; else 1-in-N cycles gets a stall
  const char *timing   = nullptr;
  const char *known    = "";   // opcodes whose failures are recorded, not new
};

static FILE *OUT = nullptr;   // harness output, kept clear of the model's $display

struct Failure {
  const char *tier;
  std::string detail;
};

struct Harness {
  Vcpu6502_sst *top;
  uint8_t  mem[0x10000];
  uint32_t stamp[0x10000];
  uint32_t gen = 1;
  std::vector<uint16_t> dirty;
  long max_cycles;

  // per-case recording
  CycleRec rec[512];
  int n_rec = 0;

  uint64_t mask_hits[N_MASK_RULES] = {0, 0, 0};
  uint64_t t3_exact = 0, t3_prefetch = 0, t3_differs = 0;
  bool     late_writeback = true;   // read from the shim at startup
  uint8_t  got_a = 0, got_x = 0, got_y = 0, got_s = 0, got_p = 0;
  void sample() {
    got_a = top->o_a; got_x = top->o_x; got_y = top->o_y;
    got_s = top->o_s; got_p = top->o_p;
  }
  int last_t3 = 0;   // 0 not measured, 1 exact, 2 exact+prefetch, 3 differs
  int last_cpi = 0;  // decode-to-decode cycles of the case just run
  bool trace = false;
  long stall_rate = 0;   // gate T7: drop RDY 1 cycle in N
  uint32_t rng = 1;
  uint64_t stalls_injected = 0;
  inline uint32_t next_rand() { rng = rng * 1664525u + 1013904223u; return rng >> 16; }

  Harness(Vcpu6502_sst *t, long mc) : top(t), max_cycles(mc) {
    memset(mem, 0, sizeof mem);
    memset(stamp, 0, sizeof stamp);
  }

  inline void poke(uint16_t a, uint8_t v) {
    if (stamp[a] != gen) { stamp[a] = gen; dirty.push_back(a); }
    mem[a] = v;
  }
  void scrub() {
    for (uint16_t a : dirty) mem[a] = 0;
    dirty.clear();
    gen++;
  }

  // The memory model, matching rtl/ram_async.sv: the read port is REGISTERED.
  // The byte at the address driven in cycle N is on DI throughout cycle N+1,
  // and a write cycle does not update the read register. This is not an
  // implementation detail to gloss over - `AB = {DIMUX, ADD}` in the Arlet
  // core reads DI to form the address in the same cycle, so feeding DI
  // combinationally from the current address closes a loop that does not
  // exist in the hardware and desynchronises the whole core.
  uint8_t di_reg = 0xFF;

  struct Bus { uint16_t a; uint8_t d; bool w; bool dec; };

  // Drive the low phase of a cycle and report the bus. Does NOT take the
  // clock edge: callers that want to inspect the cycle before committing it
  // (the retire check) need to look first.
  inline Bus probe() {
    top->di = di_reg;
    top->clk = 0; top->eval();
    Bus b;
    b.a = top->ab; b.w = top->we; b.dec = top->o_decode;
    b.d = b.w ? top->dout : mem[b.a];
    return b;
  }

  // Take the clock edge that ends the cycle `b` described.
  inline void commit(const Bus &b, bool writes_enabled) {
    top->clk = 1; top->eval();
    // b.d, not top->dout: DO is combinational and has already moved on to the
    // next cycle's value by the time this eval returns.
    if (b.w) { if (writes_enabled) poke(b.a, b.d); }
    else     { di_reg = mem[b.a]; }
  }

  inline Bus cycle(bool writes_enabled) {
    Bus b = probe();
    commit(b, writes_enabled);
    return b;
  }

  // Pick a 16-byte, 16-aligned window outside page 1 that the case never
  // names. Page 1 is excluded wholesale because the reset sequence's stack
  // traffic lands there. Returns 0xFFFF if none exists, which no real case
  // produces - a case names at most ~25 addresses.
  uint16_t pick_window(const Case &c, const uint16_t *extra, int n_extra) {
    uint16_t taken[72];
    int n = 0;
    auto mark = [&](uint16_t a) { if (n < 72) taken[n++] = a; };
    for (int i = 0; i < n_extra; i++) mark(extra[i]);
    for (int i = 0; i < c.n_ram_i; i++) mark(ram_at(c.ram_i, i).addr);
    for (int i = 0; i < c.n_ram_f; i++) mark(ram_at(c.ram_f, i).addr);
    for (int i = 0; i < c.n_cyc;   i++) mark(cyc_at(c.cyc,   i).addr);
    mark((uint16_t)(0x100 + c.initial.s));
    for (uint32_t b = 0x0200; b <= 0xFFE0; b += 16) {
      bool clash = false;
      for (int i = 0; i < n && !clash; i++)
        clash = taken[i] >= b && taken[i] < b + 16;
      if (!clash) return (uint16_t)b;
    }
    return 0xFFFF;
  }

  void load_preamble(uint16_t b, const State &s) {
    const uint8_t code[16] = {
      0xA2, s.s,               // LDX #s
      0x9A,                    // TXS
      0xA9, s.p,               // LDA #p
      0x48,                    // PHA
      0xA9, s.a,               // LDA #a
      0xA2, s.x,               // LDX #x
      0xA0, s.y,               // LDY #y
      0x28,                    // PLP
      0x4C, (uint8_t)(s.pc & 0xFF), (uint8_t)(s.pc >> 8),
    };
    for (int i = 0; i < 16; i++) poke((uint16_t)(b + i), code[i]);
  }

  // Runs one case. Returns true on Tier 1 + Tier 2 pass; fills `fails`.
  bool run(uint8_t op, const Case &c, const Opts &o, std::vector<Failure> &fails) {
    n_rec = 0;

    for (int i = 0; i < c.n_ram_i; i++) {
      RamEntry e = ram_at(c.ram_i, i);
      poke(e.addr, e.val);
    }
    // JMP ($xxFF). NMOS takes the high byte from $xx00; this console crosses
    // the page. The case is still checked - against the crossed-page result -
    // so the divergence is asserted rather than skipped. That needs the
    // pointer's true high byte to be readable, hence it is kept clear of the
    // preamble window.
    const bool jmp_wrap =
        op == 0x6C && mem[(uint16_t)(c.initial.pc + 1)] == 0xFF;
    uint16_t alt_hi_addr = 0, alt_pc = 0;
    uint16_t avoid[2]; int n_avoid = 0;
    if (jmp_wrap) {
      uint16_t ptr = (uint16_t)(mem[(uint16_t)(c.initial.pc + 1)] |
                                (mem[(uint16_t)(c.initial.pc + 2)] << 8));
      alt_hi_addr = (uint16_t)(ptr + 1);
      avoid[n_avoid++] = alt_hi_addr;
    }
    uint16_t base = pick_window(c, avoid, n_avoid);
    if (base == 0xFFFF) {
      fails.push_back({"setup", "no free 16-byte window for the preamble"});
      return false;
    }
    const uint8_t saved_fffc = mem[0xFFFC], saved_fffd = mem[0xFFFD];
    load_preamble(base, c.initial);
    poke(0xFFFC, (uint8_t)(base & 0xFF));
    poke(0xFFFD, (uint8_t)(base >> 8));
    if (jmp_wrap) {
      uint16_t ptr = (uint16_t)(alt_hi_addr - 1);
      alt_pc = (uint16_t)(mem[ptr] | (mem[alt_hi_addr] << 8));
      avoid[n_avoid++] = alt_pc;
      mask_hits[MASK_JMP_IND_WRAP]++;
    }

    top->reset = 1; top->rdy = 1; top->irq = 0; top->nmi = 0;
    rng = (uint32_t)(c.initial.pc * 2654435761u) | 1u;
    di_reg = 0xFF;
    for (int i = 0; i < 3; i++) cycle(false);
    top->reset = 0;

    // Phase A: reset vector, then the preamble, until the JMP's high operand
    // is read. Writes are applied (PHA needs to land) but never inside the
    // preamble window, so a stray reset-time stack write cannot corrupt it.
    bool preamble_done = false;
    long guard = 0;
    while (!preamble_done) {
      if (++guard > 400) {
        fails.push_back({"setup", "preamble never reached its JMP"});
        return false;
      }
      Bus b = probe();
      bool in_window = b.a >= base && b.a < (uint16_t)(base + 16);
      commit(b, !in_window);
      if (trace) fprintf(OUT, "    A %3ld  %04X %s %02X\n", guard, b.a,
                         b.w ? "w" : "r", b.d);
      if (!b.w && b.a == (uint16_t)(base + 15)) preamble_done = true;
    }

    // Phase B: the next read at the case's PC is the case's first cycle. It is
    // left uncommitted - phase C re-drives the same low phase.
    guard = 0;
    for (;;) {
      if (++guard > 16) {
        fails.push_back({"setup", "JMP did not arrive at the case PC"});
        return false;
      }
      Bus b = probe();
      if (trace) fprintf(OUT, "    B %3ld  %04X %s\n", guard, b.a, b.w ? "w" : "r");
      if (!b.w && b.a == c.initial.pc) break;
      commit(b, true);
    }

    // The preamble is over. Put back what it borrowed: the reset vector, and
    // the case's own RAM (which covers the byte PHA pushed through).
    poke(0xFFFC, saved_fffc);
    poke(0xFFFD, saved_fffd);
    for (int i = 0; i < c.n_ram_i; i++) {
      RamEntry e = ram_at(c.ram_i, i);
      poke(e.addr, e.val);
    }

    // Phase C: the instruction itself. It ends at the SECOND decode cycle -
    // the first belongs to this instruction, the second to the next one. That
    // second decode cycle is still clocked, because its edge is where the
    // register and flag writes of the instruction under test land; but its bus
    // activity belongs to the next instruction and is not recorded.
    int decode_count = 0;
    bool retired = false;
    uint16_t got_pc = 0;
    for (long k = 0; k < max_cycles; k++) {
      // Gate T7. Drop RDY for 1..3 cycles before an arbitrary cycle and
      // require the instruction to come out identical. The core gates WE with
      // RDY, so a stalled write presents nothing; a stalled cycle re-drives
      // the same address, which is why it is not recorded.
      if (stall_rate && (next_rand() % (uint32_t)stall_rate) == 0) {
        int n = 1 + (int)(next_rand() % 3);
        top->rdy = 0;
        for (int i = 0; i < n; i++) {
          Bus sb = probe();
          if (sb.w) {
            fails.push_back({"T7", "WE asserted while RDY was low"});
            return false;
          }
          commit(sb, false);
          stalls_injected++;
        }
        top->rdy = 1;
      }
      Bus b = probe();
      if (trace) fprintf(OUT, "    C %3ld  %04X %s %02X%s\n", k, b.a,
                         b.w ? "w" : "r", b.d, b.dec ? "  <decode>" : "");
      if (b.dec && ++decode_count == 2) {
        // o_pc is only meaningful while o_decode is high, on either core.
        got_pc = top->o_pc;
        if (!late_writeback) sample();   // state is already final
        commit(b, false);
        if (late_writeback) sample();    // ... or it lands on this edge
        retired = true;
        break;
      }
      if (n_rec < (int)(sizeof rec / sizeof rec[0]))
        rec[n_rec++] = CycleRec{b.a, b.d, (uint8_t)(b.w ? 1 : 0)};
      commit(b, true);
    }
    if (!retired) {
      fails.push_back({"setup", top->o_trap
          ? "the core trapped: undefined opcode"
          : "instruction did not retire within the cycle cap"});
      return false;
    }

    if (n_rec < 1) {
      fails.push_back({"setup", "no cycles recorded"});
      return false;
    }
    // Decode-to-decode cycles. The recorded list runs from this
    // instruction's opcode fetch to the next one's, so dropping one end
    // gives the cycles the instruction actually occupies - the same
    // accounting the suite's `cycles` array uses.
    last_cpi = n_rec - 1;

    bool ok = true;
    char buf[256];

    // ---- Tier 1 ----
    uint8_t pmask = 0xFF;
    pmask &= ~0x30;
    bool decimal_nv = is_adc_sbc(op) && (c.initial.p & 0x08);
    if (decimal_nv) pmask &= ~0xC0;

    uint8_t got_p = this->got_p, want_p = c.final_.p;
    if ((got_p ^ want_p) & 0x30) mask_hits[MASK_PBITS45]++;
    if (decimal_nv && ((got_p ^ want_p) & 0xC0)) mask_hits[MASK_DECIMAL_NV]++;

    auto cmp8 = [&](const char *nm, uint8_t got, uint8_t want) {
      if (got == want) return;
      snprintf(buf, sizeof buf, "%s: got $%02X want $%02X", nm, got, want);
      fails.push_back({"T1", buf});
      ok = false;
    };
    const uint16_t want_pc = jmp_wrap ? alt_pc : c.final_.pc;
    if (got_pc != want_pc) {
      snprintf(buf, sizeof buf, "PC: got $%04X want $%04X", got_pc, want_pc);
      fails.push_back({"T1", buf});
      ok = false;
    }
    cmp8("A", got_a, c.final_.a);
    cmp8("X", got_x, c.final_.x);
    cmp8("Y", got_y, c.final_.y);
    cmp8("S", got_s, c.final_.s);
    if ((got_p & pmask) != (want_p & pmask)) {
      snprintf(buf, sizeof buf, "P: got $%02X want $%02X (mask $%02X, diff $%02X)",
               got_p, want_p, pmask, (uint8_t)((got_p ^ want_p) & pmask));
      fails.push_back({"T1", buf});
      ok = false;
    }
    for (int i = 0; i < c.n_ram_f; i++) {
      RamEntry e = ram_at(c.ram_f, i);
      if (mem[e.addr] != e.val) {
        snprintf(buf, sizeof buf, "ram[$%04X]: got $%02X want $%02X",
                 e.addr, mem[e.addr], e.val);
        fails.push_back({"T1", buf});
        ok = false;
      }
    }

    // ---- Tier 2 ----
    //
    // Every access is checked, including the fetch of the next opcode: the
    // suite always lists that byte (measured: 2000/2000 on each of ad, 48, 4c,
    // 20, 60, 10), so a prefetching core is not penalised for reaching it, but
    // a core that reaches anywhere ELSE still is. That is the property worth
    // having on a machine where $4000-$41FF, $E000-$EA00 and $F000-$F800 are
    // peripherals.
    auto listed_addr = [&](uint16_t addr) {
      for (int j = 0; j < c.n_ram_i; j++)
        if (ram_at(c.ram_i, j).addr == addr) return true;
      for (int j = 0; j < c.n_ram_f; j++)
        if (ram_at(c.ram_f, j).addr == addr) return true;
      for (int j = 0; j < n_avoid; j++)
        if (avoid[j] == addr) return true;   // the crossed-page JMP target
      return false;
    };
    for (int i = 0; i < n_rec; i++) {
      if (!listed_addr(rec[i].addr)) {
        snprintf(buf, sizeof buf, "cycle %d %s $%04X is not in either ram list",
                 i, rec[i].write ? "write" : "read", rec[i].addr);
        fails.push_back({"T2", buf});
        ok = false;
      }
    }

    // ---- Tier 3 (diagnostic) ----
    //
    // The recorded list runs to the end of the fetch of the NEXT opcode, which
    // the suite does not count as a cycle of this instruction. So a core whose
    // timing matches NMOS exactly still shows one extra trailing read at
    // final.pc; that case is classified `prefetch`, not `differs`.
    if (o.tier3) {
      last_t3 = 0;
      bool prefix = n_rec >= c.n_cyc;
      for (int i = 0; i < c.n_cyc && prefix; i++) {
        CycleRec want = cyc_at(c.cyc, i);
        prefix = rec[i].addr == want.addr && rec[i].val == want.val &&
                 rec[i].write == want.write;
      }
      if (prefix && n_rec == c.n_cyc) { t3_exact++; last_t3 = 1; }
      else if (prefix && n_rec == c.n_cyc + 1 && !rec[c.n_cyc].write &&
               rec[c.n_cyc].addr == got_pc) { t3_prefetch++; last_t3 = 2; }
      else {
        t3_differs++; last_t3 = 3;
        std::string s = "cycles differ\n      got : ";
        for (int i = 0; i < n_rec; i++) {
          snprintf(buf, sizeof buf, "%04X:%02X%s ", rec[i].addr, rec[i].val,
                   rec[i].write ? "w" : "r");
          s += buf;
        }
        s += "\n      want: ";
        for (int i = 0; i < c.n_cyc; i++) {
          CycleRec want = cyc_at(c.cyc, i);
          snprintf(buf, sizeof buf, "%04X:%02X%s ", want.addr, want.val,
                   want.write ? "w" : "r");
          s += buf;
        }
        fails.push_back({"T3", s});
      }
    }

    return ok;
  }
};

// ------------------------------------------------------------------- main --

static bool load_opcode_list(const char *path, bool want[N_OPCODES],
                             std::string name[N_OPCODES]) {
  FILE *f = fopen(path, "r");
  if (!f) { perror(path); return false; }
  char line[256];
  int n = 0;
  while (fgets(line, sizeof line, f)) {
    char *p = line;
    while (*p == ' ' || *p == '\t') p++;
    if (*p == '#' || *p == '\n' || *p == '\0') continue;
    unsigned op; char mn[16] = {0}, mode[16] = {0};
    if (sscanf(p, "%x %15s %15s", &op, mn, mode) < 2 || op > 0xFF) continue;
    want[op] = true;
    name[op] = std::string(mn) + " " + mode;
    n++;
  }
  fclose(f);
  fprintf(OUT, "opcode list %s: %d entries\n", path, n);
  return n > 0;
}

static double now_s() {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
  Opts o;
  std::vector<char *> vargs{argv[0]};
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&]() -> const char * { return (i + 1 < argc) ? argv[++i] : ""; };
    if      (a == "--fixture")        o.fixture = next();
    else if (a == "--opcodes")        o.opcodes = next();
    else if (a == "--cases")          o.cases = atol(next());
    else if (a == "--opcode")         o.opcode_only = (int)strtol(next(), nullptr, 16);
    else if (a == "--all-opcodes")    o.all_opcodes = true;
    else if (a == "--tier3")          o.tier3 = true;
    else if (a == "--max-report")     o.max_report = atoi(next());
    else if (a == "--max-cycles")     o.max_cycles = atol(next());
    else if (a == "--verilog-stdout") o.verilog_stdout = true;
    else if (a == "--trace")          o.trace = true;
    else if (a == "--stall")          o.stall = atol(next());
    else if (a == "--timing")         o.timing = next();
    else if (a == "--known-failures") o.known = next();
    else if (a == "--help" || a == "-h") {
      printf("usage: %s --fixture F [--cases N] [--opcode HH] [--all-opcodes]\n"
             "          [--tier3] [--opcodes FILE] [--max-report N]\n"
             "          [--max-cycles N] [--verilog-stdout] [--trace]\n"
             "          [--timing FILE] [--known-failures HH,HH] [--stall N]\n"
             "  --cases 0 runs every case in the fixture.\n", argv[0]);
      return 0;
    }
    else vargs.push_back(argv[i]);
  }
  if (!o.fixture) { fprintf(stderr, "--fixture is required\n"); return 2; }

  // The Arlet core prints reset diagnostics through $display, which at a
  // million cases would bury everything. Keep our own handle on the real
  // stdout and send the model's to /dev/null unless asked otherwise.
  OUT = fdopen(dup(fileno(stdout)), "w");
  setvbuf(OUT, nullptr, _IOLBF, 0);
  if (!o.verilog_stdout && !freopen("/dev/null", "w", stdout))
    fprintf(OUT, "warning: could not silence the model's $display\n");

  Verilated::commandArgs((int)vargs.size(), vargs.data());

  Fixture fx;
  if (!fx.open(o.fixture)) return 2;

  bool want[N_OPCODES] = {false};
  std::string name[N_OPCODES];
  if (o.all_opcodes) for (int i = 0; i < N_OPCODES; i++) want[i] = true;
  else if (!load_opcode_list(o.opcodes, want, name)) return 2;
  if (o.opcode_only >= 0) {
    for (int i = 0; i < N_OPCODES; i++) if (i != o.opcode_only) want[i] = false;
    want[o.opcode_only] = true;
  }

  // Opcodes whose failures are already understood and written up. They are
  // still run, still counted and still printed - they just do not turn the
  // exit code red, so a genuinely new failure is not lost in a target that is
  // permanently broken. An empty list is the right setting for a new core.
  bool known_fail[N_OPCODES] = {false};
  for (const char *k = o.known; *k;) {
    known_fail[(int)strtol(k, nullptr, 16) & 0xFF] = true;
    while (*k && *k != ',') k++;
    if (*k == ',') k++;
  }

  Vcpu6502_sst *top = new Vcpu6502_sst;
  Harness h(top, o.max_cycles);
  h.trace = o.trace;
  top->eval();
  h.late_writeback = top->o_late_writeback;
  h.stall_rate = o.stall;
  fprintf(OUT, "core reports state final %s the decode cycle's edge\n",
          h.late_writeback ? "after" : "before");

  uint64_t ran = 0, passed = 0;
  int cpi_min[N_OPCODES], cpi_max[N_OPCODES], nmos_min[N_OPCODES], nmos_max[N_OPCODES];
  uint64_t cpi_sum[N_OPCODES] = {0}, nmos_sum[N_OPCODES] = {0}, cpi_n[N_OPCODES] = {0};
  for (int i = 0; i < N_OPCODES; i++) { cpi_min[i] = nmos_min[i] = 999; cpi_max[i] = nmos_max[i] = 0; }
  int n_op_run = 0, n_op_fail = 0, n_op_skipped = 0;
  uint64_t reported = 0, known_failed = 0, new_failed = 0;
  std::vector<std::pair<std::string, uint64_t>> failing_ops;
  std::vector<std::pair<std::string, uint64_t>> t3_ops;

  fprintf(OUT, "65x02 conformance: suite %s, fixture %s\n",
          fx.commit.empty() ? "(unrecorded)" : fx.commit.c_str(), o.fixture);
  fprintf(OUT, "tiers 1+2 gate, tier 3 %s\n\n",
          o.tier3 ? "reported" : "off (--tier3 to enable)");

  double t0 = now_s();
  for (int op = 0; op < N_OPCODES; op++) {
    if (!want[op]) { n_op_skipped++; continue; }
    n_op_run++;
    long limit = o.cases > 0 ? o.cases : (long)fx.count[op];
    if (limit > (long)fx.count[op]) limit = (long)fx.count[op];
    const uint8_t *p = fx.base + fx.offset[op];
    uint64_t op_pass = 0, op_fail = 0, op_t3differ = 0;
    for (long i = 0; i < limit; i++) {
      Case c;
      p = fx.decode(p, c);
      std::vector<Failure> fails;
      bool ok = h.run((uint8_t)op, c, o, fails);
      ran++;
      if (ok) { passed++; op_pass++; }
      else { op_fail++; (known_fail[op] ? known_failed : new_failed)++; }
      if (h.last_t3 == 3) op_t3differ++;
      if (h.last_cpi > 0) {
        if (h.last_cpi < cpi_min[op]) cpi_min[op] = h.last_cpi;
        if (h.last_cpi > cpi_max[op]) cpi_max[op] = h.last_cpi;
        cpi_sum[op] += (uint64_t)h.last_cpi;
        if (c.n_cyc < nmos_min[op]) nmos_min[op] = c.n_cyc;
        if (c.n_cyc > nmos_max[op]) nmos_max[op] = c.n_cyc;
        nmos_sum[op] += c.n_cyc;
        cpi_n[op]++;
      }
      for (const Failure &f : fails) {
        if ((int)reported < o.max_report) {
          fprintf(OUT, "  %02X %-10s case %ld  [%s] %s\n", op,
                  name[op].empty() ? "" : name[op].c_str(), i, f.tier,
                  f.detail.c_str());
          if (strcmp(f.tier, "T3") != 0) reported++;
        }
      }
      h.last_cpi = 0;
      h.scrub();
    }
    if (op_fail) {
      if (!known_fail[op]) n_op_fail++;
      char b[64];
      snprintf(b, sizeof b, "%02X %-10s%s", op, name[op].c_str(),
               known_fail[op] ? "  (known, see docs/cpu-core.md)" : "");
      failing_ops.push_back({b, op_fail});
    }
    if (op_t3differ) {
      char b[64];
      snprintf(b, sizeof b, "%02X %s", op, name[op].c_str());
      t3_ops.push_back({b, op_t3differ});
    }
    (void)op_pass;
  }
  double dt = now_s() - t0;

  fprintf(OUT, "\n");
  fprintf(OUT, "opcodes      : %d run, %d skipped (of %d)\n",
          n_op_run, n_op_skipped, N_OPCODES);
  fprintf(OUT, "cases        : %llu run, %llu passed, %llu failed  (%.0f/s)\n",
          (unsigned long long)ran, (unsigned long long)passed,
          (unsigned long long)(ran - passed), ran / (dt > 0 ? dt : 1));
  fprintf(OUT, "cases/opcode : %s\n",
          o.cases > 0 ? std::to_string(o.cases).c_str() : "all");
  if (o.tier3)
    fprintf(OUT,
            "tier 3       : %llu cycle-exact, %llu exact plus the next opcode's\n"
            "               fetch, %llu differ   (diagnostic, never gates)\n",
            (unsigned long long)h.t3_exact, (unsigned long long)h.t3_prefetch,
            (unsigned long long)h.t3_differs);
  if (o.tier3 && !t3_ops.empty()) {
    fprintf(OUT, "  opcodes whose cycle activity differs:\n");
    for (auto &t : t3_ops)
      fprintf(OUT, "    %-14s %llu\n", t.first.c_str(),
              (unsigned long long)t.second);
  }
  if (o.stall)
    fprintf(OUT, "stall (T7)   : RDY dropped 1..3 cycles, 1 chance in %ld per cycle;\n"
                 "               %llu stall cycles injected\n",
            o.stall, (unsigned long long)h.stalls_injected);
  fprintf(OUT, "accepted divergences (counted, never silent):\n");
  for (int i = 0; i < N_MASK_RULES; i++)
    fprintf(OUT, "  %-10llu %s\n", (unsigned long long)h.mask_hits[i],
            MASK_REASON[i]);
  if (!failing_ops.empty()) {
    fprintf(OUT, "failing      : %llu cases new, %llu known\n",
            (unsigned long long)new_failed, (unsigned long long)known_failed);
    for (auto &f : failing_ops)
      fprintf(OUT, "  %-46s %llu\n", f.first.c_str(),
              (unsigned long long)f.second);
  }
  if (o.timing) {
    FILE *tf = fopen(o.timing, "w");
    if (!tf) { perror(o.timing); }
    else {
      fprintf(tf, "{\n  \"suite\": \"%s\",\n  \"cases_per_opcode\": \"%s\",\n",
              fx.commit.c_str(), o.cases > 0 ? std::to_string(o.cases).c_str() : "all");
      fprintf(tf, "  \"note\": \"cpi is decode-to-decode cycles measured on this "
                  "core; nmos is the suite's own cycle count for the same cases\",\n");
      fprintf(tf, "  \"opcodes\": {\n");
      bool first = true;
      for (int op = 0; op < N_OPCODES; op++) {
        if (!cpi_n[op]) continue;
        if (!first) fprintf(tf, ",\n");
        first = false;
        fprintf(tf,
                "    \"%02X\": {\"name\": \"%s\", \"n\": %llu, "
                "\"cpi_min\": %d, \"cpi_max\": %d, \"cpi_mean\": %.4f, "
                "\"nmos_min\": %d, \"nmos_max\": %d, \"nmos_mean\": %.4f}",
                op, name[op].c_str(), (unsigned long long)cpi_n[op],
                cpi_min[op], cpi_max[op], (double)cpi_sum[op] / cpi_n[op],
                nmos_min[op], nmos_max[op], (double)nmos_sum[op] / cpi_n[op]);
      }
      fprintf(tf, "\n  }\n}\n");
      fclose(tf);
      fprintf(OUT, "cycle table  : %s\n", o.timing);
    }
  }
  fprintf(OUT, "\n%s\n", new_failed == 0 ? "PASS" : "FAIL");

  delete top;
  return new_failed == 0 ? 0 : 1;
}
