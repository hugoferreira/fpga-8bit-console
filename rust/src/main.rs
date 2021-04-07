extern crate verilated;
extern crate verilated_module;
extern crate minifb;

use minifb::{Key, Window, WindowOptions};
use std::{sync::{Arc, Mutex, mpsc}, thread, time::{Duration, Instant}};
use verilated_module::module;

const WIDTH: usize = 160;
const HEIGHT: usize = 121;
const MAX_FPS: u32 = 25;

#[module(top)]
pub struct Top {
    #[port(clock)]  pub clk_i: bool,
    #[port(reset)]  pub rst_i: bool,
    #[port(output)] pub hsync: bool,
    #[port(output)] pub vsync: bool,
    #[port(output)] pub rgb: [bool; 24],
}

fn tickdesign_by(tb: &mut Top, clocks: &mut u64, duration: u64) {
    let target_clock = *clocks + duration;
    while *clocks < target_clock { tickdesign(tb, clocks); }
}

fn tickdesign(tb: &mut Top, clocks: &mut u64) {
    tb.trace_at(Duration::from_nanos(10 * (*clocks)));
    tb.clock_toggle();
    tb.eval();
    *clocks += 1;
}

fn resetdesign(tb: &mut Top, clocks: &mut u64) {
    *clocks = 0;
    tb.reset_toggle();
    tickdesign_by(tb, clocks, 10);
    tb.reset_toggle();
}

fn main() {    
    let buffer_read = Arc::new(Mutex::new(vec![0 as u32; WIDTH * HEIGHT]));
    let buffer_write = Arc::clone(&buffer_read);

    let (tx, rx) = mpsc::sync_channel(1);

    let _simulation_thread = thread::spawn(move || {
        let mut buffer: Vec<u32> = vec![0 as u32; WIDTH * HEIGHT];
        let mut tb = Top::default();
        let mut clocks: u64 = 0;
        let mut hpos: u32 = 0;
        let mut vpos: u32 = 0;
        let mut frame: u32 = 0;
        let mut vblank = true;
        let mut hblank = false;

        // tb.open_trace("trace.vcd", 99).unwrap();
        resetdesign(&mut tb, &mut clocks);
        let start = Instant::now();

        loop {
            tickdesign_by(&mut tb, &mut clocks, 8);

            if tb.vsync() != 0 && !vblank {
                vblank = true;
                vpos = 0;
                frame += 1;

                buffer_write.lock().unwrap().clone_from(&buffer);
                tx.send(1).unwrap();
                
                if frame % MAX_FPS == 0 { println!("Frame {} ({:?})", frame, start.elapsed()); }
            }

            if tb.vsync() == 0 && vblank { vblank = false; }

            if !vblank {
                if tb.hsync() != 0 && !hblank { hpos = 0; hblank = true; vpos += 1; } else { hpos += 1; }
                if tb.hsync() == 0 && hblank { hblank = false }
                if !hblank { (*buffer)[(vpos * 160 + hpos) as usize] = u32::from(tb.rgb()); }
            }
        }

        tb.finish(); 
    });

    let mut window_options = WindowOptions::default();
    window_options.scale = minifb::Scale::X4;
    window_options.scale_mode = minifb::ScaleMode::AspectRatioStretch;

    let mut window = Window::new(
        "Screen (ESC to Exit)",
        WIDTH,
        HEIGHT,
        window_options,
    ).unwrap_or_else(|e| { 
        panic!("{}", e); 
    });

    // Limit to max FPS update rate
    window.limit_update_rate(Some(Duration::from_micros((1000000/MAX_FPS).into())));

    while window.is_open() && !window.is_key_down(Key::Escape) {
        window.update_with_buffer(&buffer_read.lock().unwrap(), WIDTH, HEIGHT).unwrap_or_else(|e| { 
            panic!("{}", e); 
        });
        rx.recv().unwrap();
    }
}
