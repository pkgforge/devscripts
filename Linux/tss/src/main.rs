use std::env;
use std::io::{self, BufRead, BufReader, Write, BufWriter};
use std::time::{SystemTime, UNIX_EPOCH, Instant};
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
    unbuffered: bool,
    timezone: Option<String>,
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
            unbuffered: true,
            timezone: None,
        };

        let args: Vec<String> = env::args().collect();
        let mut i = 1;
        while i < args.len() {
            match args[i].as_str() {
                "-h" | "--help" => {
                    Self::print_help();
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
                "--buffered" => config.unbuffered = false,
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

        Ok(config)
    }

    fn print_help() {
        println!(
            "ts - timestamp each line of input
Usage: ts [OPTIONS]

Options:
  -f, --format FORMAT      Date format (default: %Y-%m-%d %H:%M:%S)
  -s, --separator SEP      Separator between timestamp and line (default: \" \")
  -r, --relative           Show relative timestamps from start
  -m, --monotonic          Use monotonic clock for relative timestamps
  -u, --utc                Use UTC time instead of local time
  -i, --iso                Use ISO 8601 format (2025-07-03T14:30:45.123+05:45)
  -e, --epoch              Show seconds since Unix epoch
  --microseconds           Show microseconds precision
  --nanoseconds            Show nanoseconds precision
  --delta                  Show time delta between lines
  --prefix-only            Only show timestamp prefix (no input lines)
  --color                  Colorize timestamps
  --buffered               Use buffered output (default is unbuffered)
  --timezone TZ            Use specific timezone (e.g., UTC, EST, PST)
  -h, --help               Show this help

Format specifiers (strftime compatible):
  %Y  4-digit year         %m  Month (01-12)        %d  Day (01-31)
  %H  Hour (00-23)         %M  Minute (00-59)       %S  Second (00-59)
  %3f Milliseconds         %6f Microseconds         %9f Nanoseconds
  %z  Timezone offset      %Z  Timezone name        %%  Literal %

Examples:
  ls -la | ts                          # Basic timestamping
  tail -f /var/log/messages | ts -r    # Relative timestamps
  ping google.com | ts -f \"[%H:%M:%S.%3f]\"  # Custom format
  dmesg | ts -i                        # ISO format
  make 2>&1 | ts -e                    # Epoch timestamps
  tail -f app.log | ts -r -m           # Relative monotonic
  cat file.txt | ts --delta            # Show time between lines
  ping host | ts --color --microseconds # Colored with microseconds
  command | ts --prefix-only           # Only timestamps
"
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
}

impl TimeFormatter {
    fn new(config: &Config) -> Self {
        let format_type = FormatType::from_config(config);
        
        let custom_format = if let FormatType::Custom(ref fmt) = format_type {
            Some(fmt.clone())
        } else {
            None
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
        }
    }

    #[inline]
    fn format_timestamp(&mut self, monotonic: bool) -> &str {
        self.timestamp_buf.clear();
        
        if self.color {
            self.timestamp_buf.push_str("\x1b[36m"); // Cyan color
        }
        
        match &self.format_type {
            FormatType::Delta => {
                let now = if monotonic {
                    let instant = Instant::now();
                    let duration = if let Some(last) = self.last_instant {
                        instant.duration_since(last)
                    } else {
                        std::time::Duration::from_secs(0)
                    };
                    self.last_instant = Some(instant);
                    duration
                } else {
                    let time = SystemTime::now();
                    let duration = if let Some(last) = self.last_time {
                        time.duration_since(last).unwrap_or_default()
                    } else {
                        std::time::Duration::from_secs(0)
                    };
                    self.last_time = Some(time);
                    duration
                };
                
                let total_us = now.as_micros();
                use std::fmt::Write;
                write!(self.timestamp_buf, "{}.{:06}", 
                       total_us / 1_000_000, total_us % 1_000_000).unwrap();
            },
            
            FormatType::Epoch => {
                let now = SystemTime::now();
                let secs = now.duration_since(UNIX_EPOCH).unwrap().as_secs();
                use std::fmt::Write;
                write!(self.timestamp_buf, "{}", secs).unwrap();
            },
            
            FormatType::EpochUs => {
                let now = SystemTime::now();
                let us = now.duration_since(UNIX_EPOCH).unwrap().as_micros();
                use std::fmt::Write;
                write!(self.timestamp_buf, "{}", us).unwrap();
            },
            
            FormatType::EpochNs => {
                let now = SystemTime::now();
                let ns = now.duration_since(UNIX_EPOCH).unwrap().as_nanos();
                use std::fmt::Write;
                write!(self.timestamp_buf, "{}", ns).unwrap();
            },
            
            FormatType::CommonISO => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second()).unwrap();
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second()).unwrap();
                }
            },
            
            FormatType::CommonISOMs => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:03}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_millis()).unwrap();
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:03}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_millis()).unwrap();
                }
            },
            
            FormatType::CommonISOUs => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:06}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_micros()).unwrap();
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:06}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_micros()).unwrap();
                }
            },
            
            FormatType::CommonISONs => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:09}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_nanos()).unwrap();
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:09}",
                           dt.year(), dt.month(), dt.day(),
                           dt.hour(), dt.minute(), dt.second(),
                           dt.timestamp_subsec_nanos()).unwrap();
                }
            },
            
            FormatType::ISO8601 => {
                let now = SystemTime::now();
                if self.utc {
                    let dt: DateTime<Utc> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{}", dt.format("%Y-%m-%dT%H:%M:%S%.3f%z")).unwrap();
                } else {
                    let dt: DateTime<Local> = now.into();
                    use std::fmt::Write;
                    write!(self.timestamp_buf, "{}", dt.format("%Y-%m-%dT%H:%M:%S%.3f%z")).unwrap();
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
                        let subsec_millis = duration.subsec_millis();
                        let hours = (total_secs / 3600) as u32;
                        let mins = ((total_secs % 3600) / 60) as u32;
                        let secs = (total_secs % 60) as u32;
                        
                        let dt = Utc.with_ymd_and_hms(1970, 1, 1, hours, mins, secs).unwrap()
                            .with_nanosecond(subsec_millis * 1_000_000).unwrap();
                        
                        use std::fmt::Write;
                        write!(self.timestamp_buf, "{}", dt.format(fmt)).unwrap();
                    } else {
                        let total_ms = duration.as_millis();
                        use std::fmt::Write;
                        write!(self.timestamp_buf, "{}.{:03}", 
                               total_ms / 1000, total_ms % 1000).unwrap();
                    }
                } else {
                    // Handle absolute timestamps with custom format
                    let now = SystemTime::now();
                    if let Some(ref fmt) = self.custom_format {
                        if self.utc {
                            let dt: DateTime<Utc> = now.into();
                            use std::fmt::Write;
                            write!(self.timestamp_buf, "{}", dt.format(fmt)).unwrap();
                        } else {
                            let dt: DateTime<Local> = now.into();
                            use std::fmt::Write;
                            write!(self.timestamp_buf, "{}", dt.format(fmt)).unwrap();
                        }
                    }
                }
            },
        }
        
        if self.color {
            self.timestamp_buf.push_str("\x1b[0m"); // Reset color
        }
        
        &self.timestamp_buf
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::parse_args()?;
    let mut formatter = TimeFormatter::new(&config);
    
    let stdin = io::stdin();
    let stdout = io::stdout();
    
    // Use larger buffers for better performance unless unbuffered
    let buffer_size = if config.unbuffered { 0 } else { 256 * 1024 };
    let reader = BufReader::with_capacity(128 * 1024, stdin);
    let mut writer = if config.unbuffered {
        BufWriter::with_capacity(0, stdout)
    } else {
        BufWriter::with_capacity(buffer_size, stdout)
    };
    
    let separator_bytes = config.separator.as_bytes();
    let newline = b"\n";
    
    for line_result in reader.lines() {
        let line = line_result?;
        let timestamp = formatter.format_timestamp(config.monotonic);
        
        // Write timestamp
        writer.write_all(timestamp.as_bytes())?;
        
        if !config.prefix_only {
            writer.write_all(separator_bytes)?;
            writer.write_all(line.as_bytes())?;
        }
        
        writer.write_all(newline)?;
        
        // Always flush when unbuffered (which is now default)
        if config.unbuffered {
            writer.flush()?;
        }
    }
    
    writer.flush()?;
    Ok(())
}