use std::collections::HashMap;
use std::env;
use std::fs::File;
use std::io::{self, BufRead, Write};
use std::path::Path;
use std::error::Error;

/// Parse a line of pixel data into a byte
fn parse_pixel_line(line: &str) -> u8 {
    line.chars()
        .fold(0u8, |acc, c| (acc << 1) | if c == '*' { 1 } else { 0 })
}

/// Convert a byte to a pixel line with '*' for 1 and '.' for 0
fn byte_to_pixel_line(byte: u8) -> String {
    let mut result = String::with_capacity(8);
    
    for bit_pos in 0..8 {
        // Check each bit from MSB to LSB (left to right in display)
        let bit = (byte >> (7 - bit_pos)) & 1;
        if bit == 1 {
            result.push('*');
        } else {
            result.push('.');
        }
    }
    
    result
}

/// Parse the font definition file and return a map of character codes to their patterns
fn parse_font_file<P: AsRef<Path>>(path: P) -> io::Result<HashMap<u8, Vec<u8>>> {
    let file = File::open(path)?;
    let reader = io::BufReader::new(file);
    let mut chars = HashMap::new();
    let mut current_char: Option<u8> = None;
    let mut current_pattern = Vec::new();

    for line in reader.lines() {
        let line = line?.trim().to_string();
        
        // Skip empty lines and comments
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        if line.starts_with("char") {
            // If we were parsing a character, save it
            if let Some(code) = current_char {
                chars.insert(code, current_pattern);
                current_pattern = Vec::new();
            }

            // Parse the character code
            let code = line.split('#')
                .next()
                .and_then(|s| s.split_whitespace().nth(1))
                .and_then(|s| u8::from_str_radix(&s.trim_start_matches("0x"), 16).ok())
                .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "Invalid character code"))?;

            current_char = Some(code);
        } else if line.contains('.') || line.contains('*') {
            let pattern = parse_pixel_line(&line);
            current_pattern.push(pattern);
        }
    }

    // Save the last character
    if let Some(code) = current_char {
        chars.insert(code, current_pattern);
    }

    Ok(chars)
}

/// Parse a hex font file and return an array of bytes
fn parse_hex_file<P: AsRef<Path>>(path: P) -> io::Result<Vec<u8>> {
    let file = File::open(path)?;
    let reader = io::BufReader::new(file);
    let mut bytes = Vec::new();

    for line in reader.lines() {
        let line = line?.trim().to_string();
        if line.is_empty() {
            continue;
        }

        // Parse the hex value
        let byte = u8::from_str_radix(&line, 16)
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "Invalid hex value"))?;
        bytes.push(byte);
    }

    Ok(bytes)
}

/// Generate the hex file with all 256 characters
fn generate_hex_file<P: AsRef<Path>>(chars: &HashMap<u8, Vec<u8>>, path: P) -> io::Result<()> {
    let mut file = File::create(path)?;
    
    // Write all 256 characters
    for code in 0..=255u8 {
        let default_pattern = vec![0; 8];
        let pattern = chars.get(&code).unwrap_or(&default_pattern);
        for (i, &row) in pattern.iter().take(8).enumerate() {
            // Only write newline for all but the very last byte
            let is_last_byte = code == 255 && i == 7;
            if is_last_byte {
                write!(file, "{:02x}", row)?;
            } else {
                writeln!(file, "{:02x}", row)?;
            }
        }
    }

    Ok(())
}

/// Generate the text font file from a parsed hex file
fn generate_font_file<P: AsRef<Path>>(hex_bytes: Vec<u8>, path: P) -> io::Result<()> {
    let mut file = File::create(path)?;
    
    // Process 256 characters (8 bytes per character)
    for char_idx in 0..256 {
        // Write character header
        writeln!(file, "char 0x{:02x}", char_idx)?;
        
        // Get 8 bytes for this character
        let start_idx = char_idx * 8;
        if start_idx + 8 <= hex_bytes.len() {
            let default_byte = 0;
            // Convert each byte to a line of pixels and write to file
            for i in 0..8 {
                let byte_idx = start_idx + i;
                let byte = if byte_idx < hex_bytes.len() { hex_bytes[byte_idx] } else { default_byte };
                let line = byte_to_pixel_line(byte);
                writeln!(file, "{}", line)?;
            }
        } else {
            // If we don't have data for this character, output empty lines
            for _ in 0..8 {
                writeln!(file, "........")?;
            }
        }
        
        // Add a blank line between characters
        writeln!(file)?;
    }
    
    Ok(())
}

/// Generate a hex file from a text font file
fn text_to_hex(text_path: &Path, hex_path: &Path) -> Result<(), Box<dyn Error>> {
    let chars = parse_font_file(text_path)?;
    generate_hex_file(&chars, hex_path)?;
    Ok(())
}

/// Generate a text font file from a hex file
fn hex_to_text(hex_path: &Path, text_path: &Path) -> Result<(), Box<dyn Error>> {
    let hex_bytes = parse_hex_file(hex_path)?;
    generate_font_file(hex_bytes, text_path)?;
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = env::args().collect();
    
    if args.len() != 4 {
        eprintln!("Usage: {} <mode> <input_path> <output_path>", args[0]);
        eprintln!("Modes: text2hex, hex2text");
        return Err("Invalid arguments".into());
    }
    
    let mode = &args[1];
    let input_path = Path::new(&args[2]);
    let output_path = Path::new(&args[3]);
    
    match mode.as_str() {
        "text2hex" => text_to_hex(input_path, output_path),
        "hex2text" => hex_to_text(input_path, output_path),
        _ => {
            eprintln!("Unknown mode: {}", mode);
            eprintln!("Modes: text2hex, hex2text");
            Err("Invalid mode".into())
        }
    }
} 