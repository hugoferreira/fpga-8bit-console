module chip(input clk, input reset, output sda, output scl, output cs, output rs);
  wire vsync;
  wire hsync;
  wire [7:0] vpos;
  wire [7:0] hpos;

  wire grid_gfx = (((hpos&7)==0) && ((vpos&7)==0));
  
  wire [4:0] red   = (ball_gfx | ball_hgfx) ? 5'b11111 : 0; 
  wire [5:0] green = (ball_gfx | grid_gfx) ? 6'b111111 : 0; 
  wire [4:0] blue  = (ball_gfx | ball_vgfx) ? 5'b11111 : 0; 

  rotatescreen lcd0(
    .cin(clk),
    .reset,
    .red,
    .green,
    .blue,
    .sda,
    .scl,
    .cs,
    .rs,
    .vsync,
    .vpos,
    .hpos
  ); 

  reg [8:0] ball_hpos;	// ball current X position
  reg [8:0] ball_vpos;	// ball current Y position
  
  reg [8:0] ball_horiz_move = -2;	// ball current X velocity
  reg [8:0] ball_vert_move = 2;		// ball current Y velocity
  
  localparam ball_horiz_initial = 60;	// ball initial X position
  localparam ball_vert_initial = 60;	// ball initial Y position
  
  localparam BALL_SIZE = 4;		// ball size (in pixels)

  // update horizontal timer
  always @(posedge vsync or posedge reset)
  begin
    if (reset) begin
      // reset ball position to center
      ball_hpos <= ball_horiz_initial;
      ball_vpos <= ball_vert_initial;
    end else begin
      // add velocity vector to ball position
      ball_hpos <= ball_hpos + ball_horiz_move;
      ball_vpos <= ball_vpos + ball_vert_move;
    end
  end

  // vertical bounce
  always @(posedge ball_vert_collide)
  begin
    ball_vert_move <= -ball_vert_move;
  end

  // horizontal bounce
  always @(posedge ball_horiz_collide)
  begin
    ball_horiz_move <= -ball_horiz_move;
  end

  // offset of ball position from video beam
  wire [8:0] ball_hdiff = hpos - ball_hpos;
  wire [8:0] ball_vdiff = vpos - ball_vpos;

  // ball graphics output
  wire ball_hgfx = ball_hdiff < BALL_SIZE;
  wire ball_vgfx = ball_vdiff < BALL_SIZE;
  wire ball_gfx = ball_hgfx && ball_vgfx;

  // collide with vertical and horizontal boundaries
  // these are set when the ball touches a border
  wire ball_vert_collide = ball_vpos >= 127 - BALL_SIZE;
  wire ball_horiz_collide = ball_hpos >= 159 - BALL_SIZE;

endmodule
