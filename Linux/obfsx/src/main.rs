use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process;
use blake3;

const DEFAULT_OFFSET: usize = 64;
const DEFAULT_MAGIC: &[u8] = b"\x00\x00\x00\x00";
const OBFUSCATED_EXT: &str = "obfsx";
const MIN_FILE_SIZE: usize = 3;
const MAX_MAGIC_SIZE: usize = 8;
const MIN_OFFSET: usize = 3;
const BLAKE3_HASH_SIZE: usize = 32;
const VERSION_BYTE: u8 = 0x01; // Format version for future compatibility
const MAX_AUTO_CHECKSUM_SIZE: usize = 100 * 1024 * 1024; // 100MB

#[derive(Debug, Clone)]
struct Config {
    command: Option<Command>,
    input_file: PathBuf,
    output_file: Option<PathBuf>,
    force: bool,
    inplace: bool,
    magic: Vec<u8>,
    offset: usize,
    quiet: bool,
    verbose: bool,
    checksum: Option<bool>, // None = auto-detect, Some(true) = force enable, Some(false) = disable
    verify_only: bool,
}

#[derive(Debug, Clone, PartialEq)]
enum Command {
    Obfuscate,
    Deobfuscate,
    Verify,
}

#[derive(Debug)]
struct ObfuscationHeader {
    signature: [u8; 4],      // "OBFX"
    version: u8,             // Format version
    flags: u8,               // Bit flags (0x01 = has checksum)
    magic_len: u8,           // Length of original magic bytes
    reserved: u8,            // Reserved for future use
    original_length: u32,    // Original file length
    checksum: [u8; BLAKE3_HASH_SIZE], // BLAKE3 hash of original file
}

impl ObfuscationHeader {
    const SIZE: usize = 4 + 1 + 1 + 1 + 1 + 4 + BLAKE3_HASH_SIZE; // 44 bytes
    
    fn new(original_length: u32, magic_len: u8, checksum: Option<[u8; BLAKE3_HASH_SIZE]>) -> Self {
        let flags = if checksum.is_some() { 0x01 } else { 0x00 };
        Self {
            signature: *b"OBFX",
            version: VERSION_BYTE,
            flags,
            magic_len,
            reserved: 0,
            original_length,
            checksum: checksum.unwrap_or([0; BLAKE3_HASH_SIZE]),
        }
    }
    
    fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(Self::SIZE);
        bytes.extend_from_slice(&self.signature);
        bytes.push(self.version);
        bytes.push(self.flags);
        bytes.push(self.magic_len);
        bytes.push(self.reserved);
        bytes.extend_from_slice(&self.original_length.to_le_bytes());
        bytes.extend_from_slice(&self.checksum);
        bytes
    }
    
    fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() < Self::SIZE {
            return Err("Header too small".to_string());
        }
        
        let signature = [bytes[0], bytes[1], bytes[2], bytes[3]];
        if signature != *b"OBFX" {
            return Err("Invalid header signature".to_string());
        }
        
        let version = bytes[4];
        if version != VERSION_BYTE {
            return Err(format!("Unsupported format version: {}", version));
        }
        
        let flags = bytes[5];
        let magic_len = bytes[6];
        let reserved = bytes[7];
        
        let original_length = u32::from_le_bytes([
            bytes[8], bytes[9], bytes[10], bytes[11]
        ]);
        
        let mut checksum = [0u8; BLAKE3_HASH_SIZE];
        checksum.copy_from_slice(&bytes[12..12 + BLAKE3_HASH_SIZE]);
        
        Ok(Self {
            signature,
            version,
            flags,
            magic_len,
            reserved,
            original_length,
            checksum,
        })
    }
    
    fn has_checksum(&self) -> bool {
        self.flags & 0x01 != 0
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            command: None,
            input_file: PathBuf::new(),
            output_file: None,
            force: false,
            inplace: false,
            magic: DEFAULT_MAGIC.to_vec(),
            offset: DEFAULT_OFFSET,
            quiet: false,
            verbose: false,
            checksum: None, // Auto-detect based on file size
            verify_only: false,
        }
    }
}

fn resolve_path(path: &str) -> Result<PathBuf, String> {
    let path = Path::new(path);
    
    // Convert to absolute path
    let absolute_path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        env::current_dir()
            .map_err(|e| format!("Failed to get current directory: {}", e))?
            .join(path)
    };
    
    // Resolve symlinks and canonicalize
    absolute_path.canonicalize()
        .or_else(|_| {
            // If canonicalize fails (e.g., file doesn't exist), try to resolve parent
            if let Some(parent) = absolute_path.parent() {
                if parent.exists() {
                    let canonical_parent = parent.canonicalize()
                        .map_err(|e| format!("Failed to resolve parent directory: {}", e))?;
                    if let Some(filename) = absolute_path.file_name() {
                        Ok(canonical_parent.join(filename))
                    } else {
                        Err("Invalid path structure".to_string())
                    }
                } else {
                    Err("Parent directory does not exist".to_string())
                }
            } else {
                Err("Cannot resolve path".to_string())
            }
        })
        .map_err(|e| format!("Failed to resolve path '{}': {}", path.display(), e))
}

fn create_parent_directories(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        if !parent.exists() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create parent directories for '{}': {}", path.display(), e))?;
        }
    }
    Ok(())
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
                "verify" | "check" => {
                    config.command = Some(Command::Verify);
                    config.verify_only = true;
                    i = 2;
                }
                _ => {
                    // Not a command, treat as input file
                    config.input_file = PathBuf::from(first_arg);
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
            "-c" | "--checksum" => config.checksum = Some(true),
            "--no-checksum" => config.checksum = Some(false),
            "--verify" => {
                config.command = Some(Command::Verify);
                config.verify_only = true;
            }
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
                    return Err(format!("Offset must be at least {} (increased to accommodate header)", MIN_OFFSET));
                }
            }
            "-w" | "--write-to" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing value for --write-to".to_string());
                }
                config.output_file = Some(PathBuf::from(&args[i]));
            }
            arg if arg.starts_with('-') => {
                return Err(format!("Unknown option: {}", arg));
            }
            _ => {
                // Positional arguments
                if config.input_file.as_os_str().is_empty() {
                    config.input_file = PathBuf::from(&args[i]);
                } else if config.output_file.is_none() && !config.verify_only {
                    config.output_file = Some(PathBuf::from(&args[i]));
                } else {
                    return Err("Too many positional arguments".to_string());
                }
            }
        }
        i += 1;
    }
    
    if config.input_file.as_os_str().is_empty() {
        return Err("No input file specified".to_string());
    }
    
    // Resolve input file path and symlinks
    config.input_file = resolve_path(&config.input_file.to_string_lossy())?;
    
    // Resolve output file path if specified
    if let Some(ref output_file) = config.output_file {
        // For output files that may not exist yet, we need special handling
        let output_str = output_file.to_string_lossy().to_string();
        config.output_file = Some(if output_file.exists() {
            resolve_path(&output_str)?
        } else {
            // If output file doesn't exist, resolve parent and append filename
            if output_file.is_absolute() {
                output_file.to_path_buf()
            } else {
                env::current_dir()
                    .map_err(|e| format!("Failed to get current directory: {}", e))?
                    .join(output_file)
            }
        });
    }
    
    // Validate conflicting options
    if config.inplace && config.output_file.is_some() {
        return Err("Cannot use --inplace with --write-to".to_string());
    }
    
    if config.verify_only && (config.inplace || config.output_file.is_some()) {
        return Err("Cannot use output options with --verify".to_string());
    }
    
    // Ensure minimum offset can accommodate header
    if config.offset < ObfuscationHeader::SIZE + config.magic.len() {
        config.offset = ObfuscationHeader::SIZE + config.magic.len();
        if !config.quiet {
            eprintln!("Warning: Offset increased to {} to accommodate header and magic bytes", config.offset);
        }
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

fn calculate_blake3_hash(data: &[u8]) -> [u8; BLAKE3_HASH_SIZE] {
    let hash = blake3::hash(data);
    *hash.as_bytes()
}

fn should_use_checksum(config: &Config, file_size: usize) -> Result<bool, String> {
    match config.checksum {
        Some(force) => Ok(force),
        None => {
            if file_size > MAX_AUTO_CHECKSUM_SIZE {
                if !config.quiet {
                    eprintln!("Warning: File size ({} bytes) exceeds auto-checksum limit ({} bytes)",
                             file_size, MAX_AUTO_CHECKSUM_SIZE);
                    eprintln!("Use -c/--checksum to force checksum generation, or --no-checksum to disable");
                }
                Ok(false)
            } else {
                Ok(true)
            }
        }
    }
}

fn run(config: Config) -> Result<(), String> {
    // Validate input file exists and get metadata
    if !config.input_file.exists() {
        return Err(format!("Input file '{}' does not exist", config.input_file.display()));
    }
    
    let metadata = fs::metadata(&config.input_file)
        .map_err(|e| format!("Failed to read file metadata: {}", e))?;
    
    if !metadata.is_file() {
        return Err(format!("'{}' is not a regular file", config.input_file.display()));
    }
    
    let file_size = metadata.len() as usize;
    if file_size < MIN_FILE_SIZE && !config.force {
        return Err(format!(
            "File too small to process ({} bytes, minimum {}). Use --force to override", 
            file_size, MIN_FILE_SIZE
        ));
    }
    
    // Read input file
    let data = fs::read(&config.input_file)
        .map_err(|e| format!("Failed to read input file: {}", e))?;
    
    if data.len() != file_size {
        return Err("File size mismatch during read".to_string());
    }
    
    // Determine operation if not specified
    let command = config.command.clone().unwrap_or_else(|| {
        if is_obfuscated(&data, &config.magic) {
            if config.verify_only {
                Command::Verify
            } else {
                Command::Deobfuscate
            }
        } else {
            Command::Obfuscate
        }
    });
    
    match command {
        Command::Verify => verify_file(&data, &config),
        Command::Obfuscate => {
            let use_checksum = should_use_checksum(&config, data.len())?;
            let result_data = obfuscate(&data, &config.magic, config.offset, use_checksum)?;
            write_output(&config, &data, &result_data, Command::Obfuscate)
        }
        Command::Deobfuscate => {
            let result_data = deobfuscate(&data, &config.magic, config.offset, config.verbose)?;
            write_output(&config, &data, &result_data, Command::Deobfuscate)
        }
    }
}

fn verify_file(data: &[u8], config: &Config) -> Result<(), String> {
    if !is_obfuscated(data, &config.magic) {
        return Err("File does not appear to be obfuscated".to_string());
    }
    
    let header = extract_header(data, config.offset)?;
    
    if !config.quiet {
        println!("File verification results:");
        println!("  Format version: {}", header.version);
        println!("  Original length: {} bytes", header.original_length);
        println!("  Has checksum: {}", header.has_checksum());
        println!("  Magic length: {} bytes", header.magic_len);
    }
    
    if header.has_checksum() {
        // Perform temporary deobfuscation to verify checksum
        let deobfuscated = deobfuscate(data, &config.magic, config.offset, false)?;
        let calculated_hash = calculate_blake3_hash(&deobfuscated);
        
        if calculated_hash == header.checksum {
            if !config.quiet {
                println!("  Checksum: VALID ✓");
            }
        } else {
            return Err("Checksum verification FAILED - file may be corrupted".to_string());
        }
    } else {
        if !config.quiet {
            println!("  Checksum: Not present");
        }
    }
    
    if !config.quiet {
        println!("File verification: PASSED ✓");
    }
    
    Ok(())
}

fn write_output(config: &Config, original_data: &[u8], result_data: &[u8], command: Command) -> Result<(), String> {
    // Determine output file
    let output_file = if config.inplace {
        config.input_file.clone()
    } else {
        config.output_file.clone().unwrap_or_else(|| {
            match command {
                Command::Obfuscate => {
                    config.input_file.with_extension(
                        format!("{}.{}", 
                            config.input_file.extension()
                                .map(|ext| ext.to_string_lossy())
                                .unwrap_or_default(),
                            OBFUSCATED_EXT
                        )
                    )
                }
                Command::Deobfuscate => {
                    let stem = config.input_file.file_stem()
                        .map(|s| s.to_string_lossy().to_string())
                        .unwrap_or_else(|| "deobfuscated".to_string());
                    
                    // Check if it ends with .obfsx and remove it
                    if stem.ends_with(&format!(".{}", OBFUSCATED_EXT)) {
                        let new_stem = &stem[..stem.len() - OBFUSCATED_EXT.len() - 1];
                        config.input_file
                            .parent()
                            .unwrap_or_else(|| Path::new("."))
                            .join(new_stem)
                    } else {
                        config.input_file.with_file_name(format!("{}_deobfuscated", stem))
                    }
                }
                Command::Verify => unreachable!(),
            }
        })
    };
    
    // Create parent directories if needed
    create_parent_directories(&output_file)?;
    
    // Check for overwrite protection
    if !config.force && !config.inplace && output_file.exists() {
        return Err(format!("Output file '{}' exists. Use --force to overwrite", output_file.display()));
    }
    
    // Write with atomic operation
    let temp_file = output_file.with_extension(
        format!("{}.tmp", 
            output_file.extension()
                .map(|ext| ext.to_string_lossy())
                .unwrap_or_else(|| "tmp".into())
        )
    );
    
    fs::write(&temp_file, result_data)
        .map_err(|e| format!("Failed to write temporary file: {}", e))?;
    
    // Atomic rename
    fs::rename(&temp_file, &output_file)
        .map_err(|e| {
            let _ = fs::remove_file(&temp_file);
            format!("Failed to finalize output file: {}", e)
        })?;
    
    // Output info
    if !config.quiet {
        let operation = match command {
            Command::Obfuscate => "Obfuscated",
            Command::Deobfuscate => "Deobfuscated",
            Command::Verify => unreachable!(),
        };
        
        if config.verbose {
            println!("{}: {} -> {}", operation, config.input_file.display(), output_file.display());
            println!("Magic bytes: {:02X?}", config.magic);
            println!("Offset: {}", config.offset);
            println!("Original size: {} bytes", original_data.len());
            println!("Result size: {} bytes", result_data.len());
            
            if command == Command::Obfuscate {
                let use_checksum = should_use_checksum(config, original_data.len()).unwrap_or(false);
                println!("Checksum enabled: {}", use_checksum);
            }
        } else {
            println!("{}: {} -> {}", operation, config.input_file.display(), output_file.display());
        }
    }
    
    Ok(())
}

fn extract_header(data: &[u8], offset: usize) -> Result<ObfuscationHeader, String> {
    if data.len() < offset + ObfuscationHeader::SIZE {
        return Err("File too small to contain header".to_string());
    }
    
    ObfuscationHeader::from_bytes(&data[offset..offset + ObfuscationHeader::SIZE])
}

fn is_obfuscated(data: &[u8], magic: &[u8]) -> bool {
    if data.len() < magic.len() {
        return false;
    }
    
    // Check if current magic bytes match our obfuscation magic
    &data[..magic.len()] == magic
}

fn obfuscate(data: &[u8], magic: &[u8], offset: usize, use_checksum: bool) -> Result<Vec<u8>, String> {
    if data.len() < magic.len() {
        return Err(format!("File too small to obfuscate ({} bytes, need at least {})", data.len(), magic.len()));
    }
    
    // Verify file is not already obfuscated
    if is_obfuscated(data, magic) {
        return Err("File appears to already be obfuscated".to_string());
    }
    
    let original_len = data.len();
    let mut result = data.to_vec();
    
    // Calculate required size
    let required_size = offset + ObfuscationHeader::SIZE + magic.len();
    if result.len() < required_size {
        result.resize(required_size, 0);
    }
    
    // Store original magic bytes after the header
    let original_magic = result[..magic.len()].to_vec();
    let magic_storage_offset = offset + ObfuscationHeader::SIZE;
    
    // Ensure we have space for original magic
    if magic_storage_offset + magic.len() > result.len() {
        result.resize(magic_storage_offset + magic.len(), 0);
    }
    
    result[magic_storage_offset..magic_storage_offset + magic.len()].copy_from_slice(&original_magic);
    
    // Calculate checksum if enabled
    let checksum = if use_checksum {
        Some(calculate_blake3_hash(data))
    } else {
        None
    };
    
    // Create and store header
    let header = ObfuscationHeader::new(original_len as u32, magic.len() as u8, checksum);
    let header_bytes = header.to_bytes();
    result[offset..offset + ObfuscationHeader::SIZE].copy_from_slice(&header_bytes);
    
    // Replace file magic bytes with obfuscation magic
    result[..magic.len()].copy_from_slice(magic);
    
    Ok(result)
}

fn deobfuscate(data: &[u8], magic: &[u8], offset: usize, verbose: bool) -> Result<Vec<u8>, String> {
    // Verify this is an obfuscated file
    if !is_obfuscated(data, magic) {
        return Err("File does not appear to be obfuscated with this magic".to_string());
    }
    
    if data.len() < offset + ObfuscationHeader::SIZE {
        return Err("File too small or corrupted for deobfuscation".to_string());
    }
    
    // Extract and validate header
    let header = extract_header(data, offset)?;
    
    if header.magic_len as usize != magic.len() {
        return Err("Magic byte length mismatch".to_string());
    }
    
    let magic_storage_offset = offset + ObfuscationHeader::SIZE;
    if data.len() < magic_storage_offset + magic.len() {
        return Err("File too small to contain stored magic bytes".to_string());
    }
    
    let mut result = data.to_vec();
    
    // Restore original magic bytes
    let stored_magic = &data[magic_storage_offset..magic_storage_offset + magic.len()];
    result[..magic.len()].copy_from_slice(stored_magic);
    
    // Trim to original length if it was extended
    let original_len = header.original_length as usize;
    if original_len > 0 && original_len <= result.len() {
        result.truncate(original_len);
    } else if original_len > result.len() {
        return Err("Original length exceeds current file size - file may be corrupted".to_string());
    }
    
    // Verify checksum if present
    if header.has_checksum() {
        let calculated_hash = calculate_blake3_hash(&result);
        if calculated_hash != header.checksum {
            return Err("Checksum verification failed - file may be corrupted".to_string());
        }
        if verbose {
            println!("Checksum verification: PASSED ✓");
        }
    }
    
    Ok(result)
}

fn print_help(program_name: &str) {
    println!("High-Performance Magic Byte Obfuscator with BLAKE3 Integrity Checking");
    println!();
    println!("USAGE:");
    println!("    {} [COMMAND] <INPUT_FILE> [OUTPUT_FILE] [OPTIONS]", program_name);
    println!();
    println!("COMMANDS:");
    println!("    of, obf, obfuscate      Obfuscate the file");
    println!("    df, deobf, deobfuscate  Deobfuscate the file");
    println!("    check, verify           Verify obfuscated file integrity");
    println!("    (auto-detect if no command specified)");
    println!();
    println!("OPTIONS:");
    println!("    -c, --checksum      Force enable BLAKE3 checksum (auto-enabled for files < 100MB)");
    println!("    --no-checksum       Disable checksum generation");
    println!("    -f, --force         Force overwrite existing files and bypass size checks");
    println!("    -h, --help          Show this help message");
    println!("    -i, --inplace       Modify the original file directly");
    println!("    -m, --magic <BYTES> Custom magic bytes (hex: 0xDEADBEEF or raw)");
    println!("    -o, --offset <NUM>  Custom offset for header storage (min: {}, default: {})", MIN_OFFSET, DEFAULT_OFFSET);
    println!("    -q, --quiet         Silent operation");
    println!("    -v, --verbose       Verbose output with detailed information");
    println!("    --verify            Verify file integrity without deobfuscation");
    println!("    -w, --write-to <FILE> Custom output file path");
    println!();
    println!("EXAMPLES:");
    println!("    {} image.png                       # Auto-detect and process", program_name);
    println!("    {} obf document.pdf secret.bin     # Obfuscate with custom output", program_name);
    println!("    {} deobf -i secret.bin             # Deobfuscate in-place", program_name);  
    println!("    {} -m 0xDEADBEEF -c -o 64 file.exe # Custom magic, force checksum, custom offset", program_name);
    println!("    {} verify secret.bin               # Verify file integrity", program_name);
    println!("    {} --no-checksum large_file.bin    # Disable checksum for large files", program_name);
    println!();
    println!("Default magic bytes: {:02X?}", DEFAULT_MAGIC);
    println!("Default offset: {} bytes", DEFAULT_OFFSET);
    println!("Default obfuscated extension: .{}", OBFUSCATED_EXT);
    println!("BLAKE3 hash size: {} bytes", BLAKE3_HASH_SIZE);
}