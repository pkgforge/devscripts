use std::env;
use std::fs;
use std::path::Path;
use std::process;

const DEFAULT_OFFSET: usize = 24;
const DEFAULT_MAGIC: &[u8] = b"\x00\x00\x00\x00";
const OBFUSCATED_EXT: &str = "obfsx";
const MIN_FILE_SIZE: usize = 3;
const MAX_MAGIC_SIZE: usize = 8;
const MIN_OFFSET: usize = 4;

#[derive(Debug, Clone)]
struct Config {
    command: Option<Command>,
    input_file: String,
    output_file: Option<String>,
    force: bool,
    inplace: bool,
    magic: Vec<u8>,
    offset: usize,
    quiet: bool,
    verbose: bool,
}

#[derive(Debug, Clone, PartialEq)]
enum Command {
    Obfuscate,
    Deobfuscate,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            command: None,
            input_file: String::new(),
            output_file: None,
            force: false,
            inplace: false,
            magic: DEFAULT_MAGIC.to_vec(),
            offset: DEFAULT_OFFSET,
            quiet: false,
            verbose: false,
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let program_name = Path::new(&args[0])
        .file_name()
        .unwrap_or_else(|| std::ffi::OsStr::new("obfsx"))
        .to_string_lossy();

    let config = match parse_args(&args) {
        Ok(config) => config,
        Err(e) => {
            eprintln!("Error: {}", e);
            print_help(&program_name);
            process::exit(1);
        }
    };

    if let Err(e) = run(config) {
        eprintln!("Error: {}", e);
        process::exit(1);
    }
}

fn parse_args(args: &[String]) -> Result<Config, String> {
    if args.len() < 2 {
        return Err("No input file specified".to_string());
    }

    let mut config = Config::default();
    let mut i = 1;

    // Check if first arg is a command or flag
    if let Some(first_arg) = args.get(1) {
        if first_arg == "-h" || first_arg == "--help" {
            let program_name = Path::new(&args[0])
                .file_name()
                .unwrap_or_else(|| std::ffi::OsStr::new("obfsx"))
                .to_string_lossy();
            print_help(&program_name);
            process::exit(0);
        }

        if !first_arg.starts_with('-') {
            match first_arg.as_str() {
                "of" | "obf" | "obfuscate" => {
                    config.command = Some(Command::Obfuscate);
                    i = 2;
                }
                "df" | "deobf" | "deobfuscate" => {
                    config.command = Some(Command::Deobfuscate);
                    i = 2;
                }
                _ => {
                    // Not a command, treat as input file
                    config.input_file = first_arg.clone();
                    i = 2;
                }
            }
        }
    }

    // Parse remaining arguments
    while i < args.len() {
        match args[i].as_str() {
            "-f" | "--force" => config.force = true,
            "-h" | "--help" => {
                let program_name = Path::new(&args[0])
                    .file_name()
                    .unwrap_or_else(|| std::ffi::OsStr::new("obfsx"))
                    .to_string_lossy();
                print_help(&program_name);
                process::exit(0);
            }
            "-i" | "--inplace" => config.inplace = true,
            "-q" | "--quiet" => config.quiet = true,
            "-v" | "--verbose" => config.verbose = true,
            "-m" | "--magic" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing value for --magic".to_string());
                }
                config.magic = parse_magic_bytes(&args[i])?;
            }
            "-o" | "--offset" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing value for --offset".to_string());
                }
                config.offset = args[i].parse()
                    .map_err(|_| "Invalid offset value".to_string())?;
                if config.offset < MIN_OFFSET {
                    return Err(format!("Offset must be at least {}", MIN_OFFSET));
                }
            }
            "-w" | "--write-to" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing value for --write-to".to_string());
                }
                config.output_file = Some(args[i].clone());
            }
            arg if arg.starts_with('-') => {
                return Err(format!("Unknown option: {}", arg));
            }
            _ => {
                // Positional arguments
                if config.input_file.is_empty() {
                    config.input_file = args[i].clone();
                } else if config.output_file.is_none() {
                    config.output_file = Some(args[i].clone());
                } else {
                    return Err("Too many positional arguments".to_string());
                }
            }
        }
        i += 1;
    }

    if config.input_file.is_empty() {
        return Err("No input file specified".to_string());
    }

    // Validate conflicting options
    if config.inplace && config.output_file.is_some() {
        return Err("Cannot use --inplace with --write-to".to_string());
    }

    Ok(config)
}

fn parse_magic_bytes(s: &str) -> Result<Vec<u8>, String> {
    if s.is_empty() {
        return Err("Magic bytes cannot be empty".to_string());
    }

    let bytes = if s.starts_with("0x") || s.starts_with("\\x") {
        // Hex format: 0xDEADBEEF or \xDE\xAD\xBE\xEF
        let hex_str = s.replace("0x", "").replace("\\x", "");
        if hex_str.len() % 2 != 0 {
            return Err("Hex string must have even length".to_string());
        }
        
        (0..hex_str.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex_str[i..i + 2], 16))
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| "Invalid hex format".to_string())?
    } else {
        // Raw bytes
        s.as_bytes().to_vec()
    };

    if bytes.len() > MAX_MAGIC_SIZE {
        return Err(format!("Magic bytes too long (max {} bytes)", MAX_MAGIC_SIZE));
    }

    Ok(bytes)
}

fn run(config: Config) -> Result<(), String> {
    // Validate input file exists
    if !Path::new(&config.input_file).exists() {
        return Err(format!("Input file '{}' does not exist", config.input_file));
    }

    // Read input file
    let data = fs::read(&config.input_file)
        .map_err(|e| format!("Failed to read input file: {}", e))?;

    if data.len() < MIN_FILE_SIZE && !config.force {
        return Err(format!("File too small to process ({} bytes, minimum {}). Use --force to override", data.len(), MIN_FILE_SIZE));
    }

    // Determine operation if not specified
    let command = config.command.unwrap_or_else(|| {
        if is_obfuscated(&data, &config.magic, config.offset) {
            Command::Deobfuscate
        } else {
            Command::Obfuscate
        }
    });

    // Determine output file
    let output_file = if config.inplace {
        config.input_file.clone()
    } else {
        config.output_file.unwrap_or_else(|| {
            let input_path = Path::new(&config.input_file);
            match command {
                Command::Obfuscate => {
                    format!("{}.{}", config.input_file, OBFUSCATED_EXT)
                }
                Command::Deobfuscate => {
                    if let Some(stem) = input_path.file_stem() {
                        let stem_str = stem.to_string_lossy();
                        if stem_str.ends_with(&format!(".{}", OBFUSCATED_EXT)) {
                            let new_stem = &stem_str[..stem_str.len() - OBFUSCATED_EXT.len() - 1];
                            if let Some(parent) = input_path.parent() {
                                parent.join(new_stem).to_string_lossy().to_string()
                            } else {
                                new_stem.to_string()
                            }
                        } else {
                            format!("{}_deobfuscated", config.input_file)
                        }
                    } else {
                        format!("{}_deobfuscated", config.input_file)
                    }
                }
            }
        })
    };

    // Check for overwrite protection
    if !config.force && !config.inplace && Path::new(&output_file).exists() {
        return Err(format!("Output file '{}' exists. Use --force to overwrite", output_file));
    }

    // Perform operation
    let result_data = match command {
        Command::Obfuscate => obfuscate(&data, &config.magic, config.offset)?,
        Command::Deobfuscate => deobfuscate(&data, &config.magic, config.offset)?,
    };

    // Write output
    fs::write(&output_file, &result_data)
        .map_err(|e| format!("Failed to write output file: {}", e))?;

    // Output info
    if !config.quiet {
        let operation = match command {
            Command::Obfuscate => "Obfuscated",
            Command::Deobfuscate => "Deobfuscated",
        };
        
        if config.verbose {
            println!("{}: {} -> {}", operation, config.input_file, output_file);
            println!("Magic bytes: {:02X?}", config.magic);
            println!("Offset: {}", config.offset);
            println!("Original size: {} bytes", data.len());
            println!("Result size: {} bytes", result_data.len());
        } else {
            println!("{}: {} -> {}", operation, config.input_file, output_file);
        }
    }

    Ok(())
}

fn is_obfuscated(data: &[u8], magic: &[u8], offset: usize) -> bool {
    if data.len() < offset + magic.len() + 4 {  // +4 for length storage
        return false;
    }
    
    // Check if current magic bytes match our obfuscation magic
    let current_magic = &data[..magic.len().min(data.len())];
    if current_magic != magic {
        return false;
    }
    
    // Check if there are stored original magic bytes at offset
    let stored_magic = &data[offset..offset + magic.len()];
    stored_magic != magic && !stored_magic.iter().all(|&b| b == 0)
}

fn obfuscate(data: &[u8], magic: &[u8], offset: usize) -> Result<Vec<u8>, String> {
    if data.len() < magic.len() {
        return Err(format!("File too small to obfuscate ({} bytes, need at least {})", data.len(), magic.len()));
    }

    let original_len = data.len();
    let mut result = data.to_vec();
    
    // Always extend file if necessary to accommodate offset
    if result.len() < offset + magic.len() + 4 {  // +4 for storing original length
        result.resize(offset + magic.len() + 4, 0);
    }

    // Store original magic bytes at offset
    let original_magic = result[..magic.len()].to_vec();
    result[offset..offset + magic.len()].copy_from_slice(&original_magic);
    
    // Store original file length at offset + magic.len()
    let len_bytes = (original_len as u32).to_le_bytes();
    result[offset + magic.len()..offset + magic.len() + 4].copy_from_slice(&len_bytes);
    
    // Replace magic bytes with obfuscation magic
    result[..magic.len()].copy_from_slice(magic);

    Ok(result)
}

fn deobfuscate(data: &[u8], magic: &[u8], offset: usize) -> Result<Vec<u8>, String> {
    if data.len() < offset + magic.len() + 4 {
        return Err("File too small or corrupted for deobfuscation".to_string());
    }

    // Verify this is an obfuscated file
    if &data[..magic.len()] != magic {
        return Err("File does not appear to be obfuscated with this magic".to_string());
    }

    let mut result = data.to_vec();
    
    // Restore original magic bytes from offset
    let stored_magic = data[offset..offset + magic.len()].to_vec();
    result[..magic.len()].copy_from_slice(&stored_magic);
    
    // Get original file length
    let len_bytes = &data[offset + magic.len()..offset + magic.len() + 4];
    let original_len = u32::from_le_bytes([len_bytes[0], len_bytes[1], len_bytes[2], len_bytes[3]]) as usize;
    
    // Trim to original length if it was extended
    if original_len > 0 && original_len < result.len() {
        result.truncate(original_len);
    }

    Ok(result)
}

fn print_help(program_name: &str) {
    println!("High-Performance Magic Byte Obfuscator");
    println!();
    println!("USAGE:");
    println!("    {} [COMMAND] <INPUT_FILE> [OUTPUT_FILE] [OPTIONS]", program_name);
    println!();
    println!("COMMANDS:");
    println!("    of, obf, obfuscate      Obfuscate the file");
    println!("    df, deobf, deobfuscate  Deobfuscate the file");
    println!("    (auto-detect if no command specified)");
    println!();
    println!("OPTIONS:");
    println!("    -f, --force         Force overwrite existing files");
    println!("    -h, --help          Show this help message");
    println!("    -i, --inplace       Modify the original file directly");
    println!("    -m, --magic <BYTES> Custom magic bytes (hex: 0xDEADBEEF or raw)");
    println!("    -o, --offset <NUM>  Custom offset for storing original magic (default: {})", DEFAULT_OFFSET);
    println!("    -q, --quiet         Silent operation");
    println!("    -v, --verbose       Verbose output");
    println!("    -w, --write-to <FILE> Custom output file path");
    println!();
    println!("EXAMPLES:");
    println!("    {} image.png                    # Auto-detect and process", program_name);
    println!("    {} obf document.pdf secret.bin  # Obfuscate with custom output", program_name);
    println!("    {} deobf -i secret.bin          # Deobfuscate in-place", program_name);  
    println!("    {} -m 0xDEADBEEF -o 32 file.exe # Custom magic and offset", program_name);
    println!();
    println!("Default magic bytes: {:02X?}", DEFAULT_MAGIC);
    println!("Default offset: {} bytes", DEFAULT_OFFSET);
    println!("Default obfuscated extension: .{}", OBFUSCATED_EXT);
}