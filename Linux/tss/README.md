### ℹ️ About
Timestamp each line of Input Stream like [ts(1)](https://linux.die.net/man/1/ts).<br>

### 🧰 Usage
```mathematica

❯ tss --help

tss - timestamp each line of input

Usage: tss [OPTIONS]

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
  -s, --separator SEP      Separator between timestamp and line (default: " ")
  --timezone TZ            Use specific timezone (e.g., UTC, EST, PST)
  -u, --utc                Use UTC time instead of local time

Format specifiers (strftime compatible):
  %Y  4-digit year         %m  Month (01-12)        %d  Day (01-31)
  %H  Hour (00-23)         %M  Minute (00-59)       %S  Second (00-59)
  %3f Milliseconds         %6f Microseconds         %9f Nanoseconds
  %z  Timezone offset      %Z  Timezone name        %%  Literal %

Examples:
  ls -la | tss                                             # Basic timestamping
  tail -f /var/log/messages | tss -r                       # Relative timestamps
  ping google.com | tss -f "[%H:%M:%S.%3f]➜ "              # Custom format
  dmesg | tss -i                                           # ISO format
  make 2>&1 | tss -e                                       # Epoch timestamps
  tail -f app.log | tss -r -m                              # Relative monotonic
  cat file.txt | tss --delta                               # Show time between lines
  ping host | tss --color --microseconds                   # Colored with microseconds
  command | tss --prefix-only                              # Only timestamps
  make 2>&1 | tss -o build.log                             # Append to file
  tail -f app.log | tss -o logs/app.log --force-overwrite  # Overwrite file
  ping host | tss -o network.log                           # Append to network.log

Note: --relative and --delta are mutually exclusive
      Output files are appended to by default, use --force-overwrite to replace

```

### 🛠️ Building
```bash
RUST_TARGET="$(uname -m)-unknown-linux-musl"
RUSTFLAGS="-C target-feature=+crt-static \
           -C link-self-contained=yes \
           -C default-linker-libraries=yes \
           -C prefer-dynamic=no \
           -C lto=yes \
           -C debuginfo=none \
           -C strip=symbols \
           -C link-arg=-Wl,--build-id=none \
           -C link-arg=-Wl,--discard-all \
           -C link-arg=-Wl,--strip-all"
           
export RUST_TARGET RUSTFLAGS
rustup target add "${RUST_TARGET}"

cargo build --target "${RUST_TARGET}" \
     --all-features \
     --jobs="$(($(nproc)+1))" \
     --release

"./target/${RUST_TARGET}/release/tss" --help
```