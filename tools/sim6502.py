#!/usr/bin/env python3
"""A small NMOS 6502 interpreter, for testing this console's software off-FPGA.

Covers the 151 documented opcodes. Undocumented opcodes raise, which is the
same policy the RTL core is proposed to adopt (openspec refactor-cpu-core).

Memory is a flat 64K. Reads and writes to addresses the caller registers as
MMIO are routed to callbacks, so the PPU/PSG windows can be faked.
"""


class Sim6502:
    def __init__(self, image, reset=None):
        self.m = bytearray(image)
        if len(self.m) < 0x10000:
            self.m.extend(bytes(0x10000 - len(self.m)))
        self.readers = {}          # addr -> fn() -> value
        self.writers = {}          # addr -> fn(value)
        self.a = self.x = self.y = 0
        self.b = 0        # low half of the 16-bit accumulator AB
        self.s = 0xFD
        self.trap = None   # last TRAP #imm tag, if any
        self.wai = None    # WAI wake hook: called once per executed WAI
        self.c = self.z = self.v = self.n = self.d = 0
        self.i = 1
        self.cycles = 0
        self.pc = reset if reset is not None else self.rd16(0xFFFC)

    # ---- memory ----
    def rd(self, a):
        a &= 0xFFFF
        f = self.readers.get(a)
        return (f() & 0xFF) if f else self.m[a]

    def wr(self, a, v):
        a &= 0xFFFF
        v &= 0xFF
        f = self.writers.get(a)
        if f:
            f(v)
        else:
            self.m[a] = v

    def rd16(self, a):
        return self.rd(a) | (self.rd(a + 1) << 8)

    # ---- stack ----
    def push(self, v):
        self.m[0x100 + self.s] = v & 0xFF
        self.s = (self.s - 1) & 0xFF

    def pop(self):
        self.s = (self.s + 1) & 0xFF
        return self.m[0x100 + self.s]

    @property
    def p(self):
        return (self.n << 7 | self.v << 6 | 0x20 | self.d << 3
                | self.i << 2 | self.z << 1 | self.c)

    @p.setter
    def p(self, v):
        self.n = (v >> 7) & 1
        self.v = (v >> 6) & 1
        self.d = (v >> 3) & 1
        self.i = (v >> 2) & 1
        self.z = (v >> 1) & 1
        self.c = v & 1

    def setnz(self, v):
        v &= 0xFF
        self.z = 1 if v == 0 else 0
        self.n = (v >> 7) & 1
        return v

    # ---- addressing ----
    def _fetch(self):
        v = self.rd(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def _addr(self, mode):
        if mode == "imm":
            a = self.pc
            self.pc = (self.pc + 1) & 0xFFFF
            return a
        if mode == "zp":
            return self._fetch()
        if mode == "zpx":
            return (self._fetch() + self.x) & 0xFF
        if mode == "zpy":
            return (self._fetch() + self.y) & 0xFF
        if mode == "abs":
            lo = self._fetch()
            return lo | (self._fetch() << 8)
        if mode == "absx":
            lo = self._fetch()
            return ((lo | (self._fetch() << 8)) + self.x) & 0xFFFF
        if mode == "absy":
            lo = self._fetch()
            return ((lo | (self._fetch() << 8)) + self.y) & 0xFFFF
        if mode == "indx":
            zp = (self._fetch() + self.x) & 0xFF
            return self.rd(zp) | (self.rd((zp + 1) & 0xFF) << 8)
        if mode == "indy":
            zp = self._fetch()
            base = self.rd(zp) | (self.rd((zp + 1) & 0xFF) << 8)
            return (base + self.y) & 0xFFFF
        raise AssertionError(mode)

    # ---- ALU helpers ----
    def _adc(self, v):
        if self.d:
            al = (self.a & 0xF) + (v & 0xF) + self.c
            ah = (self.a >> 4) + (v >> 4)
            if al > 9:
                al += 6
                ah += 1
            self.z = 1 if ((self.a + v + self.c) & 0xFF) == 0 else 0
            self.n = (ah >> 3) & 1
            self.v = 0
            if ah > 9:
                ah += 6
            self.c = 1 if ah > 15 else 0
            self.a = ((ah << 4) | (al & 0xF)) & 0xFF
        else:
            t = self.a + v + self.c
            self.v = (~(self.a ^ v) & (self.a ^ t) & 0x80) >> 7
            self.c = 1 if t > 0xFF else 0
            self.a = self.setnz(t)

    def _sbc(self, v):
        if self.d:
            al = (self.a & 0xF) - (v & 0xF) - (1 - self.c)
            ah = (self.a >> 4) - (v >> 4)
            if al & 0x10:
                al -= 6
                ah -= 1
            if ah & 0x10:
                ah -= 6
            t = self.a - v - (1 - self.c)
            self.c = 0 if t & 0x100 else 1
            self.setnz(t)
            self.a = ((ah << 4) | (al & 0xF)) & 0xFF
        else:
            t = self.a - v - (1 - self.c)
            self.v = ((self.a ^ v) & (self.a ^ t) & 0x80) >> 7
            self.c = 0 if t & 0x100 else 1
            self.a = self.setnz(t)

    def _cmp(self, reg, v):
        t = reg - v
        self.c = 1 if t >= 0 else 0
        self.setnz(t)

    def _branch(self, take):
        off = self._fetch()
        if take:
            if off & 0x80:
                off -= 256
            self.pc = (self.pc + off) & 0xFFFF

    # ---- the decode table ----
    LOADS = {0xA9: "imm", 0xA5: "zp", 0xB5: "zpx", 0xAD: "abs",
             0xBD: "absx", 0xB9: "absy", 0xA1: "indx", 0xB1: "indy"}
    STORES = {0x85: "zp", 0x95: "zpx", 0x8D: "abs", 0x9D: "absx",
              0x99: "absy", 0x81: "indx", 0x91: "indy"}
    ORA = {0x09: "imm", 0x05: "zp", 0x15: "zpx", 0x0D: "abs",
           0x1D: "absx", 0x19: "absy", 0x01: "indx", 0x11: "indy"}
    AND = {0x29: "imm", 0x25: "zp", 0x35: "zpx", 0x2D: "abs",
           0x3D: "absx", 0x39: "absy", 0x21: "indx", 0x31: "indy"}
    EOR = {0x49: "imm", 0x45: "zp", 0x55: "zpx", 0x4D: "abs",
           0x5D: "absx", 0x59: "absy", 0x41: "indx", 0x51: "indy"}
    ADC = {0x69: "imm", 0x65: "zp", 0x75: "zpx", 0x6D: "abs",
           0x7D: "absx", 0x79: "absy", 0x61: "indx", 0x71: "indy"}
    SBC = {0xE9: "imm", 0xE5: "zp", 0xF5: "zpx", 0xED: "abs",
           0xFD: "absx", 0xF9: "absy", 0xE1: "indx", 0xF1: "indy"}
    CMP = {0xC9: "imm", 0xC5: "zp", 0xD5: "zpx", 0xCD: "abs",
           0xDD: "absx", 0xD9: "absy", 0xC1: "indx", 0xD1: "indy"}
    RMW = {0x06: ("asl", "zp"), 0x16: ("asl", "zpx"), 0x0E: ("asl", "abs"),
           0x1E: ("asl", "absx"),
           0x46: ("lsr", "zp"), 0x56: ("lsr", "zpx"), 0x4E: ("lsr", "abs"),
           0x5E: ("lsr", "absx"),
           0x26: ("rol", "zp"), 0x36: ("rol", "zpx"), 0x2E: ("rol", "abs"),
           0x3E: ("rol", "absx"),
           0x66: ("ror", "zp"), 0x76: ("ror", "zpx"), 0x6E: ("ror", "abs"),
           0x7E: ("ror", "absx"),
           0xE6: ("inc", "zp"), 0xF6: ("inc", "zpx"), 0xEE: ("inc", "abs"),
           0xFE: ("inc", "absx"),
           0xC6: ("dec", "zp"), 0xD6: ("dec", "zpx"), 0xCE: ("dec", "abs"),
           0xDE: ("dec", "absx")}

    # ---- add-isa-core-ergonomics, column $x3 ----
    # MOV writes memory without touching A, X, Y or any flag; ADD/SUB are
    # ADC/SBC with the carry decided by the opcode rather than by a preceding
    # clc/sec, and are binary-only. See docs/opcodes.md.
    EXT = {0x03, 0x13, 0x23, 0x33, 0x43, 0x53, 0x63, 0x73,
           0x8B, 0x9B,                      # add-isa-pointer-ops
           0x83, 0x93, 0xA3, 0xB3, 0xC3, 0xD3, 0xE3, 0xF3,   # add-isa-word-ops
           0xCB}                            # add-isa-wait: WAI

    # add-isa-word-ops, column $x3 high half. AB is the 16-bit accumulator with
    # A the high byte and B the low, and a zero-page operand is little-endian,
    # so both match the convention the corpus already used by hand. The flags
    # follow rtl/cpu6502_core.sv exactly, and the one place they differ from
    # the byte-pair sequence they replace is Z: it is set from BOTH halves
    # here, from the high byte alone there.
    WORD = {0x83: ("ldw", False), 0x93: ("stw", False), 0xA3: ("ldw", True),
            0xB3: ("addw", False), 0xC3: ("subw", False), 0xD3: ("cmpw", False),
            0xE3: ("addw", True), 0xF3: ("subw", True)}

    def _step_word(self, op):
        kind, imm = self.WORD[op]
        if op == 0x93:                       # STAB zp - a write, never a read
            zp = self._fetch()
            self.wr(zp, self.b)
            self.wr((zp + 1) & 0xFF, self.a)
            return True
        if imm:
            lo, hi = self._fetch(), self._fetch()
        else:
            zp = self._fetch()               # zp+1 wraps inside page zero
            lo, hi = self.rd(zp), self.rd((zp + 1) & 0xFF)
        if kind == "ldw":                    # LDAB: C and V untouched
            self.b, self.a = lo, hi
            self.n = (hi >> 7) & 1
            self.z = 1 if (hi == 0 and lo == 0) else 0
            return True
        sub = kind in ("subw", "cmpw")
        lo_o, hi_o = (lo ^ 0xFF, hi ^ 0xFF) if sub else (lo, hi)
        t_lo = self.b + lo_o + (1 if sub else 0)
        t_hi = self.a + hi_o + (1 if t_lo > 0xFF else 0)
        old_a = self.a
        if kind != "cmpw":
            self.b = t_lo & 0xFF
            self.a = t_hi & 0xFF
        self.n = (t_hi >> 7) & 1
        self.z = 1 if (t_hi & 0xFF) == 0 and (t_lo & 0xFF) == 0 else 0
        self.c = 1 if t_hi > 0xFF else 0
        self.v = (~(old_a ^ hi_o) & (old_a ^ t_hi) & 0x80) >> 7
        return True

    def _step_ext(self, op):
        if op in self.WORD:
            return self._step_word(op)
        if op == 0x03:                       # MOV zp, #imm
            a = self._fetch()
            self.wr(a, self._fetch())
        elif op == 0x13:                     # MOV abs, #imm
            lo = self._fetch()
            a = lo | (self._fetch() << 8)
            self.wr(a, self._fetch())
        elif op == 0x23:                     # MOV zp, abs+X
            d = self._fetch()
            lo = self._fetch()
            a = (lo | (self._fetch() << 8)) + self.x
            self.wr(d, self.rd(a & 0xFFFF))
        elif op == 0x33:                     # ADD #imm
            self._add(self._fetch(), 0)
        elif op == 0x43:                     # ADD zp
            self._add(self.rd(self._fetch()), 0)
        elif op == 0x53:                     # SUB #imm
            self._add(self._fetch() ^ 0xFF, 1)
        elif op == 0x63:                     # SUB zp
            self._add(self.rd(self._fetch()) ^ 0xFF, 1)
        elif op == 0x73:                     # TRAP #imm - inert, records
            self.trap = self._fetch()
        elif op in (0x8B, 0x9B):             # LDA/STA (zp), #disp
            zp = self._fetch()
            disp = self._fetch()
            ptr = self.m[zp] | (self.m[(zp + 1) & 0xFF] << 8)
            a = (ptr + disp) & 0xFFFF        # carries into the high byte
            if op == 0x8B:
                self.a = self.setnz(self.rd(a))
            else:
                self.wr(a, self.a)
        elif op == 0xCB:                     # WAI - sleep until the wake line.
            # The harness owns time: with no hook the instruction completes
            # immediately, which is what a rig that fakes the frame clock
            # wants. A hook models the wake source (the console's vsync).
            if self.wai is not None:
                self.wai()
        return True

    def _add(self, v, cin):
        """The shared adder: ADD is cin=0, SUB is cin=1 on an inverted operand.
        Binary only - these instructions ignore the decimal flag by design."""
        t = self.a + v + cin
        self.v = (~(self.a ^ v) & (self.a ^ t) & 0x80) >> 7
        self.c = 1 if t > 0xFF else 0
        self.a = self.setnz(t)

    def step(self):
        op = self._fetch()
        self.cycles += 1
        if op in self.EXT:
            return self._step_ext(op)

        if op in self.LOADS:
            self.a = self.setnz(self.rd(self._addr(self.LOADS[op])))
        elif op in self.STORES:
            self.wr(self._addr(self.STORES[op]), self.a)
        elif op in (0xA2, 0xA6, 0xB6, 0xAE, 0xBE):
            m = {0xA2: "imm", 0xA6: "zp", 0xB6: "zpy", 0xAE: "abs",
                 0xBE: "absy"}[op]
            self.x = self.setnz(self.rd(self._addr(m)))
        elif op in (0xA0, 0xA4, 0xB4, 0xAC, 0xBC):
            m = {0xA0: "imm", 0xA4: "zp", 0xB4: "zpx", 0xAC: "abs",
                 0xBC: "absx"}[op]
            self.y = self.setnz(self.rd(self._addr(m)))
        elif op in (0x86, 0x96, 0x8E):
            self.wr(self._addr({0x86: "zp", 0x96: "zpy", 0x8E: "abs"}[op]),
                    self.x)
        elif op in (0x84, 0x94, 0x8C):
            self.wr(self._addr({0x84: "zp", 0x94: "zpx", 0x8C: "abs"}[op]),
                    self.y)
        elif op in self.ORA:
            self.a = self.setnz(self.a | self.rd(self._addr(self.ORA[op])))
        elif op in self.AND:
            self.a = self.setnz(self.a & self.rd(self._addr(self.AND[op])))
        elif op in self.EOR:
            self.a = self.setnz(self.a ^ self.rd(self._addr(self.EOR[op])))
        elif op in self.ADC:
            self._adc(self.rd(self._addr(self.ADC[op])))
        elif op in self.SBC:
            self._sbc(self.rd(self._addr(self.SBC[op])))
        elif op in self.CMP:
            self._cmp(self.a, self.rd(self._addr(self.CMP[op])))
        elif op in (0xE0, 0xE4, 0xEC):
            self._cmp(self.x,
                      self.rd(self._addr({0xE0: "imm", 0xE4: "zp",
                                          0xEC: "abs"}[op])))
        elif op in (0xC0, 0xC4, 0xCC):
            self._cmp(self.y,
                      self.rd(self._addr({0xC0: "imm", 0xC4: "zp",
                                          0xCC: "abs"}[op])))
        elif op in (0x24, 0x2C):
            v = self.rd(self._addr("zp" if op == 0x24 else "abs"))
            self.z = 1 if (self.a & v) == 0 else 0
            self.n = (v >> 7) & 1
            self.v = (v >> 6) & 1
        elif op in self.RMW:
            kind, mode = self.RMW[op]
            a = self._addr(mode)
            v = self.rd(a)
            if kind == "asl":
                self.c = (v >> 7) & 1
                v = self.setnz(v << 1)
            elif kind == "lsr":
                self.c = v & 1
                v = self.setnz(v >> 1)
            elif kind == "rol":
                nc = (v >> 7) & 1
                v = self.setnz((v << 1) | self.c)
                self.c = nc
            elif kind == "ror":
                nc = v & 1
                v = self.setnz((v >> 1) | (self.c << 7))
                self.c = nc
            elif kind == "inc":
                v = self.setnz(v + 1)
            else:
                v = self.setnz(v - 1)
            self.wr(a, v)
        elif op == 0x0A:
            self.c = (self.a >> 7) & 1
            self.a = self.setnz(self.a << 1)
        elif op == 0x4A:
            self.c = self.a & 1
            self.a = self.setnz(self.a >> 1)
        elif op == 0x2A:
            nc = (self.a >> 7) & 1
            self.a = self.setnz((self.a << 1) | self.c)
            self.c = nc
        elif op == 0x6A:
            nc = self.a & 1
            self.a = self.setnz((self.a >> 1) | (self.c << 7))
            self.c = nc
        elif op == 0x4C:
            self.pc = self._addr("abs")
        elif op == 0x6C:
            a = self._addr("abs")
            # NMOS page-wrap bug, reproduced deliberately
            hi = (a & 0xFF00) | ((a + 1) & 0xFF)
            self.pc = self.rd(a) | (self.rd(hi) << 8)
        elif op == 0x20:
            a = self._addr("abs")
            r = (self.pc - 1) & 0xFFFF
            self.push(r >> 8)
            self.push(r & 0xFF)
            self.pc = a
        elif op == 0x60:
            lo = self.pop()
            self.pc = ((lo | (self.pop() << 8)) + 1) & 0xFFFF
        elif op == 0x40:
            self.p = self.pop()
            lo = self.pop()
            self.pc = lo | (self.pop() << 8)
        elif op == 0x00:
            raise BrkTrap(self.pc)
        elif op == 0x10:
            self._branch(not self.n)
        elif op == 0x30:
            self._branch(self.n)
        elif op == 0x50:
            self._branch(not self.v)
        elif op == 0x70:
            self._branch(self.v)
        elif op == 0x90:
            self._branch(not self.c)
        elif op == 0xB0:
            self._branch(self.c)
        elif op == 0xD0:
            self._branch(not self.z)
        elif op == 0xF0:
            self._branch(self.z)
        elif op == 0x18:
            self.c = 0
        elif op == 0x38:
            self.c = 1
        elif op == 0x58:
            self.i = 0
        elif op == 0x78:
            self.i = 1
        elif op == 0xB8:
            self.v = 0
        elif op == 0xD8:
            self.d = 0
        elif op == 0xF8:
            self.d = 1
        elif op == 0xAA:
            self.x = self.setnz(self.a)
        elif op == 0x8A:
            self.a = self.setnz(self.x)
        elif op == 0xA8:
            self.y = self.setnz(self.a)
        elif op == 0x98:
            self.a = self.setnz(self.y)
        elif op == 0xBA:
            self.x = self.setnz(self.s)
        elif op == 0x9A:
            self.s = self.x
        elif op == 0xE8:
            self.x = self.setnz(self.x + 1)
        elif op == 0xCA:
            self.x = self.setnz(self.x - 1)
        elif op == 0xC8:
            self.y = self.setnz(self.y + 1)
        elif op == 0x88:
            self.y = self.setnz(self.y - 1)
        elif op == 0x48:
            self.push(self.a)
        elif op == 0x68:
            self.a = self.setnz(self.pop())
        elif op == 0x08:
            self.push(self.p | 0x10)
        elif op == 0x28:
            self.p = self.pop()
        elif op == 0xEA:
            pass
        else:
            raise UndocumentedOpcode(op, (self.pc - 1) & 0xFFFF)

    def run(self, max_steps=5_000_000, stop_pc=None):
        for _ in range(max_steps):
            if stop_pc is not None and self.pc == stop_pc:
                return True
            self.step()
        return False

    def call(self, addr, max_steps=2_000_000):
        """Run a subroutine to its rts, using a sentinel return address."""
        sentinel = 0xFFF0
        self.push((sentinel - 1) >> 8)
        self.push((sentinel - 1) & 0xFF)
        self.pc = addr
        for _ in range(max_steps):
            if self.pc == sentinel:
                return True
            self.step()
        raise TimeoutError(f"subroutine at ${addr:04X} did not return")


class UndocumentedOpcode(Exception):
    def __init__(self, op, pc):
        super().__init__(f"undocumented opcode ${op:02X} at ${pc:04X}")


class BrkTrap(Exception):
    def __init__(self, pc):
        super().__init__(f"BRK at ${pc:04X}")
