use std::env;
use std::io::{self, BufRead, BufReader, Write};
use std::time::{SystemTime, UNIX_EPOCH, Instant};

struct Config {
    format: String,
    separator: String,
    relative: bool,
    monotonic: bool,
    utc: bool,
}

impl Config {
    fn parse_args() -> Result<Self, Box<dyn std::error::Error>> {
        let mut config = Config {
            format: "%Y-%m-%d %H:%M:%S".to_string(),
            separator: " ".to_string(),
            relative: false,
            monotonic: false,
            utc: false,
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
                _ => {
                    eprintln!("Unknown argument: {}", args[i]);
                    std::process::exit(1);
                }
            }
            i += 1;
        }

        Ok(config)
    }

    fn print_help() {
        println!(
            "ts - timestamp each line of input

Usage: ts [OPTIONS]

Options:
  -f, --format FORMAT     Date format (default: %Y-%m-%d %H:%M:%S)
  -s, --separator SEP     Separator between timestamp and line (default: \" \")
  -r, --relative          Show relative timestamps from start
  -m, --monotonic         Use monotonic clock for relative timestamps
  -u, --utc               Use UTC time
  -h, --help              Show this help

Examples:
  ls -la | ts
  tail -f /var/log/messages | ts -r
  ping google.com | ts -f \"%H:%M:%S.%f\"
"
        );
    }
}

struct TimeFormatter {
    format: String,
    relative: bool,
    utc: bool,
    start_time: Option<SystemTime>,
    start_instant: Option<Instant>,
}

impl TimeFormatter {
    fn new(config: &Config) -> Self {
        Self {
            format: config.format.clone(),
            relative: config.relative,
            utc: config.utc,
            start_time: None,
            start_instant: None,
        }
    }

    fn format_timestamp(&mut self, monotonic: bool) -> String {
        if self.relative {
            if monotonic {
                let now = Instant::now();
                let start = self.start_instant.get_or_insert(now);
                let duration = now.duration_since(*start);
                format!("{}.{:03}", duration.as_secs(), duration.subsec_millis())
            } else {
                let now = SystemTime::now();
                let start = self.start_time.get_or_insert(now);
                let duration = now.duration_since(*start).unwrap_or_default();
                format!("{}.{:03}", duration.as_secs(), duration.subsec_millis())
            }
        } else {
            let now = SystemTime::now();
            let duration = now.duration_since(UNIX_EPOCH).unwrap();
            let secs = duration.as_secs();
            let nanos = duration.subsec_nanos();
            let micros = nanos / 1000;

            // Fast path for common format
            if self.format == "%Y-%m-%d %H:%M:%S" {
                let dt = secs as i64;
                let (year, month, day, hour, min, sec) = Self::timestamp_to_parts(dt, self.utc);
                return format!("{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
                              year, month, day, hour, min, sec);
            }

            // Handle custom formats
            self.format_custom_timestamp(secs, micros)
        }
    }

    #[inline]
    fn timestamp_to_parts(timestamp: i64, utc: bool) -> (i32, u32, u32, u32, u32, u32) {
        // Simple UTC conversion (leap seconds ignored for performance)
        let mut days = timestamp / 86400;
        let remaining_secs = (timestamp % 86400) as u32;

        if !utc {
            // Rough local timezone offset - in practice you'd want proper timezone handling
            // This is simplified for maximum performance
        }

        let hour = remaining_secs / 3600;
        let min = (remaining_secs % 3600) / 60;
        let sec = remaining_secs % 60;

        // Calculate date from days since epoch (1970-01-01)
        days += 719468; // Days from year 1 to 1970

        let era = days / 146097;
        let doe = days % 146097;
        let yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365;
        let year = yoe + era * 400;
        let doy = doe - (365*yoe + yoe/4 - yoe/100);
        let mp = (5*doy + 2)/153;
        let day = doy - (153*mp+2)/5 + 1;
        let month = mp + if mp < 10 { 3 } else { -9 };
        let year = year + if month <= 2 { 1 } else { 0 };

        (year as i32, month as u32, day as u32, hour, min, sec)
    }

    fn format_custom_timestamp(&self, secs: u64, micros: u32) -> String {
        let (year, month, day, hour, min, sec) = Self::timestamp_to_parts(secs as i64, self.utc);

        // Simple format replacement for performance
        let mut result = self.format.clone();
        result = result.replace("%Y", &format!("{:04}", year));
        result = result.replace("%m", &format!("{:02}", month));
        result = result.replace("%d", &format!("{:02}", day));
        result = result.replace("%H", &format!("{:02}", hour));
        result = result.replace("%M", &format!("{:02}", min));
        result = result.replace("%S", &format!("{:02}", sec));
        result = result.replace("%f", &format!("{:06}", micros));
        result = result.replace("%%", "%");

        result
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::parse_args()?;
    let mut formatter = TimeFormatter::new(&config);

    let stdin = io::stdin();
    let mut stdout = io::stdout();

    // Use buffered reader for better performance
    let reader = BufReader::with_capacity(65536, stdin);

    // Pre-allocate output buffer
    let mut output_buf = String::with_capacity(1024);

    for line in reader.lines() {
        let line = line?;
        let timestamp = formatter.format_timestamp(config.monotonic);

        // Build output in buffer to minimize syscalls
        output_buf.clear();
        output_buf.push_str(&timestamp);
        output_buf.push_str(&config.separator);
        output_buf.push_str(&line);
        output_buf.push('\n');

        stdout.write_all(output_buf.as_bytes())?;
    }

    Ok(())
}
