use std::env;
use std::io::{self, BufRead, BufReader, Write, BufWriter};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH, Instant};
use std::fs::{create_dir_all, OpenOptions};
use chrono::{DateTime, Local, Utc, TimeZone, Timelike, Datelike};

struct Config {
    format: String,
    separator: String,
    relative: bool,
    monotonic: bool,
    utc: bool,
    iso: bool,
    since_epoch: bool,
    microseconds: bool,
    nanoseconds: bool,
    delta: bool,
    prefix_only: bool,
    color: bool,
    buffered: bool,
    timezone: Option<String>,
    output_file: Option<String>,
    force_overwrite: bool,
}

impl Config {
    fn parse_args() -> Result<Self, Box<dyn std::error::Error>> {
        let mut config = Config {
            format: "%Y-%m-%d %H:%M:%S".to_string(),
            separator: " ".to_string(),
            relative: false,
            monotonic: false,
            utc: false,
            iso: false,
            since_epoch: false,
            microseconds: false,
            nanoseconds: false,
            delta: false,
            prefix_only: false,
            color: false,
            buffered: false, // Default to unbuffered for real-time output
            timezone: None,
            output_file: None,
            force_overwrite: false,
        };
        
        let args: Vec<String> = env::args().collect();
        let program_name = Self::get_program_name(&args[0]);
        
        let mut i = 1;
        while i < args.len() {
            match args[i].as_str() {
                "-h" | "--help" => {
                    Self::print_help(&program_name);
                    std::process::exit(0);
                }
                "-r" | "--relative" => config.relative = true,
                "-m" | "--monotonic" => config.monotonic = true,
                "-u" | "--utc" => config.utc = true,
                "-i" | "--iso" => {
                    config.iso = true;
                    config.format = "%Y-%m-%dT%H:%M:%S%.3f%z".to_string();
                }
                "-e" | "--epoch" => config.since_epoch = true,
                "--microseconds" => config.microseconds = true,
                "--nanoseconds" => config.nanoseconds = true,
                "--delta" => config.delta = true,
                "--prefix-only" => config.prefix_only = true,
                "--color" => config.color = true,
                "--buffered" => config.buffered = true,
                "--force-overwrite" => config.force_overwrite = true,
                "-s" | "--separator" => {
                    i += 1;
                    if i >= args.len() {
                        eprintln!("Error: --separator requires a value");
                        std::process::exit(1);
                    }
                    config.separator = args[i].clone();
                }
                "-f" | "--format" => {
                    i += 1;
                    if i >= args.len() {
                        eprintln!("Error: --format requires a value");
                        std::process::exit(1);
                    }
                    config.format = args[i].clone();
                }
                "--timezone" => {
                    i += 1;
                    if i >= args.len() {
                        eprintln!("Error: --timezone requires a value");
                        std::process::exit(1);
                    }
                    config.timezone = Some(args[i].clone());
                }
                "-o" | "--output" => {
                    i += 1;
                    if i >= args.len() {
                        eprintln!("Error: --output requires a value");
                        std::process::exit(1);
                    }
                    config.output_file = Some(args[i].clone());
                }
                _ => {
                    eprintln!("Unknown argument: {}", args[i]);
                    std::process::exit(1);
                }
            }
            i += 1;
        }
        
        // Validation
        if config.microseconds && config.nanoseconds {
            eprintln!("Error: Cannot use both --microseconds and --nanoseconds");
            std::process::exit(1);
        }
        if config.relative && config.since_epoch {
            eprintln!("Error: Cannot use both --relative and --epoch");
            std::process::exit(1);
        }
        if config.relative && config.delta {
            eprintln!("Error: Cannot use both --relative and --delta");
            std::process::exit(1);
        }
        
        Ok(config)
    }
    
    fn get_program_name(argv0: &str) -> String {
        Path::new(argv0)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("ts")
            .to_string()
    }
    
    fn print_help(program_name: &str) {
        println!(
            "{} - timestamp each line of input stream

Usage: {} [OPTIONS]

Options:
  --buffered               Use buffered output (default is unbuffered)
  --color                  Colorize timestamps
  --delta                  Show time delta between lines 
  -e, --epoch              Show seconds since Unix epoch
  -f, --format FORMAT      Date format (default: %Y-%m-%d %H:%M:%S)
  --force-overwrite        Overwrite output file instead of appending
  -i, --iso                Use ISO 8601 format (2025-07-03T14:30:45.123+05:45)
  -h, --help               Show this help
  --microseconds           Show microseconds precision
  -m, --monotonic          Use monotonic clock for relative timestamps
  --nanoseconds            Show nanoseconds precision
  -o, --output FILE        Write timestamped output to file (appends by default)
  --prefix-only            Only show timestamp prefix (no input lines)
  -r, --relative           Show relative timestamps from start
  -s, --separator SEP      Separator between timestamp and line (default: \" \")
  --timezone TZ            Use specific timezone (e.g., UTC, EST, PST)
  -u, --utc                Use UTC time instead of local time

Format specifiers (strftime compatible):
  %Y  4-digit year         %m  Month (01-12)        %d  Day (01-31)
  %H  Hour (00-23)         %M  Minute (00-59)       %S  Second (00-59)
  %3f Milliseconds         %6f Microseconds         %9f Nanoseconds
  %z  Timezone offset      %Z  Timezone name        %%  Literal %

Examples:
  ls -la | {}                                             # Basic timestamping
  tail -f /var/log/messages | {} -r                       # Relative timestamps
  ping google.com | {} -f \"[%H:%M:%S.%3f]➜ \"              # Custom format
  dmesg | {} -i                                           # ISO format
  make 2>&1 | {} -e                                       # Epoch timestamps
  tail -f app.log | {} -r -m                              # Relative monotonic
  cat file.txt | {} --delta                               # Show time between lines
  ping host | {} --color --microseconds                   # Colored with microseconds
  command | {} --prefix-only                              # Only timestamps
  make 2>&1 | {} -o build.log                             # Append to file
  tail -f app.log | {} -o logs/app.log --force-overwrite  # Overwrite file
  ping host | {} -o network.log                           # Append to network.log

Note: --relative and --delta are mutually exclusive
      Output files are appended to by default, use --force-overwrite to replace\n",
            program_name, program_name, program_name, program_name, program_name, 
            program_name, program_name, program_name, program_name, program_name,
            program_name, program_name, program_name, program_name
        );
    }
}

#[derive(Clone)]
enum FormatType {
    CommonISO,      // %Y-%m-%d %H:%M:%S
    CommonISOMs,    // %Y-%m-%d %H:%M:%S.%3f
    CommonISOUs,    // %Y-%m-%d %H:%M:%S.%6f
    CommonISONs,    // %Y-%m-%d %H:%M:%S.%9f
    ISO8601,        // ISO format
    Epoch,          // Seconds since epoch
    EpochUs,        // Microseconds since epoch
    EpochNs,        // Nanoseconds since epoch
    Delta,          // For delta timestamps
    Custom(String), // Custom format string
}

impl FormatType {
    fn from_config(config: &Config) -> Self {
        if config.since_epoch {
            return if config.nanoseconds {
                Self::EpochNs
            } else if config.microseconds {
                Self::EpochUs
            } else {
                Self::Epoch
            };
        }
        
        if config.relative {
            // For relative timestamps, always use Custom to preserve format
            return Self::Custom(config.format.clone());
        }
        
        if config.delta {
            return Self::Delta;
        }
        
        if config.iso {
            return Self::ISO8601;
        }
        
        match config.format.as_str() {
            "%Y-%m-%d %H:%M:%S" => {
                if config.nanoseconds {
                    Self::CommonISONs
                } else if config.microseconds {
                    Self::CommonISOUs
                } else {
                    Self::CommonISO
                }
            },
            "%Y-%m-%d %H:%M:%S.%3f" => Self::CommonISOMs,
            _ => Self::Custom(config.format.clone()),
        }
    }
}

struct TimeFormatter {
    format_type: FormatType,
    utc: bool,
    relative: bool,
    start_time: Option<SystemTime>,
    start_instant: Option<Instant>,
    last_time: Option<SystemTime>,
    last_instant: Option<Instant>,
    custom_format: Option<String>,
    timestamp_buf: String,
    color: bool,
    color_prefix: &'static str,
    color_suffix: &'static str,
}

impl TimeFormatter {
    fn new(config: &Config) -> Self {
        let format_type = FormatType::from_config(config);
        
        let custom_format = if let FormatType::Custom(ref fmt) = format_type {
            Some(fmt.clone())
        } else {
            None
        };
        
        let (color_prefix, color_suffix) = if config.color {
            ("\x1b[36m", "\x1b[0m") // Cyan color
        } else {
            ("", "")
        };
        
        Self {
            format_type,
            utc: config.utc,
            relative: config.relative,
            start_time: None,
            start_instant: None,
            last_time: None,
            last_instant: None,
            custom_format,
            timestamp_buf: String::with_capacity(128),
            color: config.color,
            color_prefix,
            color_suffix,
        }
    }
    
    #[inline]
    fn format_timestamp(&mut self, monotonic: bool) -> &str {
        self.format_timestamp_impl(monotonic, true)
    }
    
    #[inline]
    fn format_timestamp_no_color(&mut self, monotonic: bool) -> &str {
        self.format_timestamp_impl(monotonic, false)
    }
    
    #[inline]
    fn format_timestamp_impl(&mut self, monotonic: bool, use_color: bool) -> &str {
        self.timestamp_buf.clear();
        
        match &self.format_type {
            FormatType::Delta => {
                let duration = if monotonic {
                    let instant = Instant::now();
                    let duration = if let Some(last) = self.last_instant {
                        instant.duration_since(last)
                    } else {
                        // Initialize with current time for first call
                        self.last_instant = Some(instant);
                        return if use_color && self.color {
                            self.timestamp_buf.push_str(self.color_prefix);
                            self.timestamp_buf.push_str("0.000000");
                            self.timestamp_buf.push_str(self.color_suffix);
                            &self.timestamp_buf
                        } else {
                            "0.000000"
                        };
                    };
                    self.last_instant = Some(instant);
                    duration
                } else {
                    let time = SystemTime::now();
                    let duration = if let Some(last) = self.last_time {
                        time.duration_since(last).unwrap_or_default()
                    } else {
                        // Initialize with current time for first call
                        self.last_time = Some(time);
                        return if use_color && self.color {
                            self.timestamp_buf.push_str(self.color_prefix);
                            self.timestamp_buf.push_str("0.000000");
                            self.timestamp_buf.push_str(self.color_suffix);
                            &self.timestamp_buf
                        } else {
                            "0.000000"
                        };
                    };
                    self.last_time = Some(time);
                    duration
                };
                
                let total_us = duration.as_micros();
                use std::fmt::Write;
                let _ = write!(self.timestamp_buf, "{}.{:06}", 
                       total_us / 1_000_000, total_us % 1_000_000);
            },
            
            FormatType::Epoch => {
                let now = SystemTime::now();
                let secs = now.duration_since(UNIX_EPOCH).unwrap().as_secs();
                use std::fmt::Write;
                let _ = write!(self.timestamp_buf, "{}", secs);
            },
            
            FormatType::EpochUs => {
                let now = SystemTime::now();
                let us = now.duration_since(UNIX_EPOCH).unwrap().as_micros();
                use std::fmt::Write;
                let _ = write!(self.timestamp_buf, "{}", us);
            },
            
            FormatType::EpochNs => {
                let now = SystemTime::now();
                let ns = now.duration_since(UNIX_EPOCH).unwrap().as_nanos();
                use std::fmt::Write;
                let _ = write!(self.timestamp_buf, "{}", ns);
            },
            
            FormatType::CommonISO => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second());
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second());
                }
            },
            
            FormatType::CommonISOMs => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:03}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_millis());
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:03}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_millis());
                }
            },
            
            FormatType::CommonISOUs => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:06}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_micros());
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:06}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_micros());
                }
            },
            
            FormatType::CommonISONs => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:09}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_nanos());
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:09}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_nanos());
                }
            },
            
            FormatType::ISO8601 => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{}", dt.format("%Y-%m-%dT%H:%M:%S%.3f%z"));
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    let _ = write!(self.timestamp_buf, "{}", dt.format("%Y-%m-%dT%H:%M:%S%.3f%z"));
                }
            },
            
            FormatType::Custom(_) => {
                if self.relative {
                    // Handle relative timestamps with custom format
                    let duration = if monotonic {
                        let now = Instant::now();
                        let start = self.start_instant.get_or_insert(now);
                        now.duration_since(*start)
                    } else {
                        let now = SystemTime::now();
                        let start = self.start_time.get_or_insert(now);
                        now.duration_since(*start).unwrap_or_default()
                    };
                    
                    if let Some(ref fmt) = self.custom_format {
                        // For relative timestamps, create a time from the duration
                        let total_secs = duration.as_secs();
                        let subsec_nanos = duration.subsec_nanos();
                        let hours = (total_secs / 3600) as u32;
                        let mins = ((total_secs % 3600) / 60) as u32;
                        let secs = (total_secs % 60) as u32;
                        
                        let dt = Utc.with_ymd_and_hms(1970, 1, 1, hours, mins, secs).unwrap()
                            .with_nanosecond(subsec_nanos).unwrap();
                        
                        use std::fmt::Write;
                        let _ = write!(self.timestamp_buf, "{}", dt.format(fmt));
                    } else {
                        let total_ms = duration.as_millis();
                        use std::fmt::Write;
                        let _ = write!(self.timestamp_buf, "{}.{:03}", 
                               total_ms / 1000, total_ms % 1000);
                    }
                } else {
                    // Handle absolute timestamps with custom format
                    let now = SystemTime::now();
                    if let Some(ref fmt) = self.custom_format {
                        if self.utc {
                            let dt: DateTime<Utc> = now.into();
                            use std::fmt::Write;
                            let _ = write!(self.timestamp_buf, "{}", dt.format(fmt));
                        } else {
                            let dt: DateTime<Local> = now.into();
                            use std::fmt::Write;
                            let _ = write!(self.timestamp_buf, "{}", dt.format(fmt));
                        }
                    }
                }
            },
        }
        
        // Add color codes if needed - do this outside the timestamp buffer
        // to avoid reallocation on every call
        if use_color && self.color {
            // Create a temporary string with color codes
            let colored = format!("{}{}{}", self.color_prefix, self.timestamp_buf, self.color_suffix);
            self.timestamp_buf = colored;
        }
        
        &self.timestamp_buf
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::parse_args()?;
    let mut formatter = TimeFormatter::new(&config);
    
    let stdin = io::stdin();
    let stdout = io::stdout();
    
    // Set up output file if specified
    let mut file_writer = if let Some(ref output_path) = config.output_file {
        // Create parent directories if they don't exist
        if let Some(parent) = Path::new(output_path).parent() {
            create_dir_all(parent)?;
        }
        
        // Open file for writing (append by default, create/truncate if force_overwrite)
        let file = if config.force_overwrite {
            OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(output_path)?
        } else {
            OpenOptions::new()
                .create(true)
                .write(true)
                .append(true)
                .open(output_path)?
        };
        
        Some(BufWriter::new(file))
    } else {
        None
    };
    
    // Use appropriate buffer sizes based on configuration
    let buffer_size = if config.buffered { 256 * 1024 } else { 0 };
    let reader = BufReader::with_capacity(128 * 1024, stdin);
    let mut writer = BufWriter::with_capacity(buffer_size, stdout);
    
    let separator_bytes = config.separator.as_bytes();
    let newline = b"\n";
    
    for line_result in reader.lines() {
        let line = line_result?;
        let timestamp = formatter.format_timestamp(config.monotonic);
        
        // Prepare the complete output line
        let mut output_line = Vec::new();
        output_line.extend_from_slice(timestamp.as_bytes());
        
        if !config.prefix_only {
            output_line.extend_from_slice(separator_bytes);
            output_line.extend_from_slice(line.as_bytes());
        }
        
        output_line.extend_from_slice(newline);
        
        // Write to stdout
        writer.write_all(&output_line)?;
        
        // Write to file if specified (without color codes for clean file output)
        if let Some(ref mut file_writer) = file_writer {
            if config.color {
                // Strip color codes for file output
                let clean_timestamp = formatter.format_timestamp_no_color(config.monotonic);
                let mut clean_output = Vec::new();
                clean_output.extend_from_slice(clean_timestamp.as_bytes());
                
                if !config.prefix_only {
                    clean_output.extend_from_slice(separator_bytes);
                    clean_output.extend_from_slice(line.as_bytes());
                }
                
                clean_output.extend_from_slice(newline);
                file_writer.write_all(&clean_output)?;
            } else {
                file_writer.write_all(&output_line)?;
            }
            
            // Flush file writer if not buffered
            if !config.buffered {
                file_writer.flush()?;
            }
        }
        
        // Flush stdout when unbuffered
        if !config.buffered {
            writer.flush()?;
        }
    }
    
    writer.flush()?;
    if let Some(ref mut file_writer) = file_writer {
        file_writer.flush()?;
    }
    Ok(())
}