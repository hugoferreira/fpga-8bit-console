// Audio-RAM port-borrow and hold regression.
//
// Exercises the freezeable core directly, including borrowed synthesis reads,
// replay, and CPU writes during a hold. It also checks that the production
// adapter matches the core when the core's explicit freeze input is low.

`timescale 1ns/1ps
`include "psg_aram.sv"

module psg_aram_hold_tb;
  bit clk;
  bit reset;
  bit cs, rw;
  logic [7:0] addr, di;
  logic [12:0] seq_addr, syn_addr;
  logic syn_rd, syn_freeze, seq_hold;
  logic [7:0] core_seq_q, adapter_seq_q;
  logic core_seq_frozen, adapter_seq_frozen;

  psg_aram_core core_dut(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di),
    .cpu_rd(1'b0), .cpu_q(),
    .seq_addr(seq_addr), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .syn_freeze(syn_freeze), .seq_hold(seq_hold),
    .seq_q(core_seq_q), .seq_frozen(core_seq_frozen));

  // The production adapter exposes top-level arbitration through seq_hold and
  // fixes the core's explicit synthesis-freeze input low.
  psg_aram adapter_dut(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di),
    .cpu_rd(1'b0), .cpu_q(),
    .seq_addr(seq_addr), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .seq_hold(seq_hold), .seq_q(adapter_seq_q),
    .seq_frozen(adapter_seq_frozen));

  always #5 clk = ~clk;

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  task automatic held_step(input logic [7:0] expected_q);
    begin
      step();
      if (core_seq_q !== expected_q || !core_seq_frozen)
        $fatal(1, "freeze changed borrow state q=%h frozen=%b expected=%h/1",
               core_seq_q, core_seq_frozen, expected_q);
    end
  endtask

  task automatic upload(input logic [12:0] index,
                        input logic [7:0] value,
                        input logic held,
                        input logic [7:0] held_q);
    logic [15:0] pico_addr;
    begin
      pico_addr = 16'h3100 + {3'd0, index};
      cs = 1'b1;
      rw = 1'b1;
      addr = 8'h00;
      di = pico_addr[7:0];
      if (held) held_step(held_q); else step();
      addr = 8'h01;
      di = pico_addr[15:8];
      if (held) held_step(held_q); else step();
      addr = 8'h02;
      di = value;
      if (held) held_step(held_q); else step();
      cs = 1'b0;
      rw = 1'b0;
      addr = 8'd0;
      di = 8'd0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    cs = 1'b0;
    rw = 1'b0;
    addr = 8'd0;
    di = 8'd0;
    seq_addr = 13'd0;
    syn_addr = 13'd0;
    syn_rd = 1'b0;
    syn_freeze = 1'b0;
    seq_hold = 1'b1;
    step();
    step();
    reset = 1'b0;

    upload(13'h020, 8'ha1, 1'b0, 8'd0);
    upload(13'h021, 8'hb2, 1'b0, 8'd0);
    upload(13'h100, 8'h5c, 1'b0, 8'd0);

    // Establish the sequencer byte that synthesis borrows the port from.
    seq_addr = 13'h100;
    seq_hold = 1'b0;
    step();
    if (core_seq_q !== 8'h5c || core_seq_frozen)
      $fatal(1, "ordinary sequencer read failed q=%h frozen=%b",
             core_seq_q, core_seq_frozen);
    seq_hold = 1'b1;

    // W0-like synthesis borrow.  Its byte and pending replay must survive an
    // arbitrary external hold, even while the independent CPU port writes.
    syn_addr = 13'h020;
    syn_rd = 1'b1;
    step();
    if (core_seq_q !== 8'ha1 || !core_seq_frozen)
      $fatal(1, "first synthesis borrow failed q=%h frozen=%b",
             core_seq_q, core_seq_frozen);
    syn_rd = 1'b0;
    syn_freeze = 1'b1;
    upload(13'h101, 8'hd4, 1'b1, 8'ha1);
    held_step(8'ha1);

    // Resume directly into the adjacent W1-like borrow.  The first byte is
    // still consumable before this edge; the edge captures the second byte
    // while preserving the one pending sequencer replay.
    syn_freeze = 1'b0;
    syn_addr = 13'h021;
    syn_rd = 1'b1;
    step();
    if (core_seq_q !== 8'hb2 || !core_seq_frozen)
      $fatal(1, "adjacent synthesis borrow failed q=%h frozen=%b",
             core_seq_q, core_seq_frozen);

    // The first non-borrow edge performs exactly one forced replay, even
    // though the sequencer is otherwise held.  It also observes the CPU byte
    // written while the synthesis side was frozen.
    syn_rd = 1'b0;
    seq_addr = 13'h101;
    if (!core_seq_frozen)
      $fatal(1, "pending replay disappeared before replay edge");
    step();
    if (core_seq_q !== 8'hd4 || core_seq_frozen)
      $fatal(1, "sequencer replay failed q=%h frozen=%b",
             core_seq_q, core_seq_frozen);
    step();
    if (core_seq_q !== 8'hd4 || core_seq_frozen)
      $fatal(1, "held sequencer output changed after replay");

    // Reset only the borrow state, then compare the production adapter with
    // the core in the adapter's fixed-low synthesis-freeze mode.
    reset = 1'b1;
    step();
    reset = 1'b0;
    syn_freeze = 1'b0;
    seq_addr = 13'h100;
    seq_hold = 1'b0;
    step();
    if (core_seq_q !== adapter_seq_q ||
        core_seq_frozen !== adapter_seq_frozen)
      $fatal(1, "audio-RAM adapter differs on ordinary read");
    seq_hold = 1'b1;
    syn_addr = 13'h020;
    syn_rd = 1'b1;
    step();
    if (core_seq_q !== adapter_seq_q ||
        core_seq_frozen !== adapter_seq_frozen)
      $fatal(1, "audio-RAM adapter differs on synthesis borrow");
    syn_rd = 1'b0;
    step();
    if (core_seq_q !== adapter_seq_q ||
        core_seq_frozen !== adapter_seq_frozen)
      $fatal(1, "audio-RAM adapter differs on sequencer replay");

    $display("psg_aram_hold_tb: PASS");
    $finish;
  end
endmodule
