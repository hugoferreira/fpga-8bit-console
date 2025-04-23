module addressdecoder_tb;
  // Test signals
  logic [15:0] addr;
  logic rw;
  logic [7:0] tb_do;
  logic [7:0] sp_do;
  logic [7:0] ram_do;
  logic [7:0] cpu_di;
  logic tb_cs;
  logic sp_cs;
  logic ram_cs;

  // Initialize test data
  initial begin
    tb_do = 8'hAA;
    sp_do = 8'hBB;
    ram_do = 8'hCC;
  end

  // Instantiate the address decoder
  addressdecoder dut(
    .addr(addr),
    .rw(rw),
    .tb_do(tb_do),
    .sp_do(sp_do),
    .ram_do(ram_do),
    .cpu_di(cpu_di),
    .tb_cs(tb_cs),
    .sp_cs(sp_cs),
    .ram_cs(ram_cs)
  );

  // Test procedure
  initial begin
    $display("Starting Address Decoder Test");
    
    // Test Main RAM region ($0000-$0FFF)
    $display("\nTesting Main RAM region:");
    addr = 16'h0000; rw = 0;
    #10ns;
    $display("Addr: $%04X, RAM_CS: %b, CPU_DI: $%02X", addr, ram_cs, cpu_di);
    
    addr = 16'h0FFF; rw = 0;
    #10ns;
    $display("Addr: $%04X, RAM_CS: %b, CPU_DI: $%02X", addr, ram_cs, cpu_di);

    // Test Sprite RAM region ($4000-$40FF)
    $display("\nTesting Sprite RAM region:");
    addr = 16'h4000; rw = 0;
    #10ns;
    $display("Addr: $%04X, SP_CS: %b, CPU_DI: $%02X", addr, sp_cs, cpu_di);
    
    addr = 16'h40FF; rw = 0;
    #10ns;
    $display("Addr: $%04X, SP_CS: %b, CPU_DI: $%02X", addr, sp_cs, cpu_di);

    // Test Text Character RAM region ($F000-$F3FF)
    $display("\nTesting Text Character RAM region:");
    addr = 16'hF000; rw = 0;
    #10ns;
    $display("Addr: $%04X, TB_CS: %b, CPU_DI: $%02X", addr, tb_cs, cpu_di);
    
    addr = 16'hF3FF; rw = 0;
    #10ns;
    $display("Addr: $%04X, TB_CS: %b, CPU_DI: $%02X", addr, tb_cs, cpu_di);

    // Test Text Attribute RAM region ($F400-$F7FF)
    $display("\nTesting Text Attribute RAM region:");
    addr = 16'hF400; rw = 0;
    #10ns;
    $display("Addr: $%04X, TB_CS: %b, CPU_DI: $%02X", addr, tb_cs, cpu_di);
    
    addr = 16'hF7FF; rw = 0;
    #10ns;
    $display("Addr: $%04X, TB_CS: %b, CPU_DI: $%02X", addr, tb_cs, cpu_di);

    // Test Vector region ($FFFC-$FFFF)
    $display("\nTesting Vector region:");
    addr = 16'hFFFC; rw = 0;
    #10ns;
    $display("Addr: $%04X, RAM_CS: %b, CPU_DI: $%02X", addr, ram_cs, cpu_di);
    
    addr = 16'hFFFF; rw = 0;
    #10ns;
    $display("Addr: $%04X, RAM_CS: %b, CPU_DI: $%02X", addr, ram_cs, cpu_di);

    // Test boundary conditions
    $display("\nTesting boundary conditions:");
    addr = 16'h0FFF; rw = 0;  // Last address of RAM
    #10ns;
    $display("Addr: $%04X, RAM_CS: %b", addr, ram_cs);
    
    addr = 16'h1000; rw = 0;  // First address after RAM
    #10ns;
    $display("Addr: $%04X, RAM_CS: %b", addr, ram_cs);
    
    addr = 16'h40FF; rw = 0;  // Last address of Sprite RAM
    #10ns;
    $display("Addr: $%04X, SP_CS: %b", addr, sp_cs);
    
    addr = 16'h4100; rw = 0;  // First address after Sprite RAM
    #10ns;
    $display("Addr: $%04X, SP_CS: %b", addr, sp_cs);

    $display("\nAddress Decoder Test Complete");
    $finish;
  end

endmodule 