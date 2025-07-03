use std::env;
use std::fs;
use std::io::{self, Write, BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use clap::{Parser, ValueEnum};
use regex::Regex;
use glob::glob;
use anyhow::{Result, Context, bail};
use thiserror::Error;
use tracing::{info, debug, error, warn};
use tokio::fs as async_fs;
use tokio::io::{AsyncBufReadExt, BufReader as AsyncBufReader};

const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Error, Debug)]
pub enum RenameError {
    #[error("Invalid regex pattern: {0}")]
    InvalidRegex(#[from] regex::Error),
    #[error("File operation failed: {0}")]
    FileOperation(#[from] io::Error),
    #[error("Backup creation failed for {file}: {source}")]
    BackupFailed { file: String, source: io::Error },
    #[error("Command execution failed: {command}")]
    CommandFailed { command: String },
    #[error("Null byte in filename: {filename}")]
    NullByteInFilename { filename: String },
    #[error("Incompatible options: {message}")]
    IncompatibleOptions { message: String },
}

#[derive(Debug, Clone, ValueEnum)]
#[clap(rename_all = "lowercase")]
enum VersionControl {
    None,
    Off,
    Nil,
    Existing,
    Numbered,
    T,
    Never,
    Simple,
}

#[derive(Parser)]
#[command(name = "rename")]
#[command(version = VERSION)]
#[command(about = "Rename multiple files using regular expressions")]
#[command(long_about = "Rename FILE(s) using REGEX pattern and replacement on each filename.")]
struct Args {
    /// Make backup before removal
    #[arg(short = 'b', long)]
    backup: bool,

    /// Copy file instead of rename
    #[arg(short = 'c', long)]
    copy: bool,

    /// Use COMMAND instead of rename
    #[arg(short = 'C', long, value_name = "COMMAND")]
    command: Option<String>,

    /// Set backup filename prefix
    #[arg(short = 'B', long, value_name = "PREFIX")]
    prefix: Option<String>,

    /// Remove existing destinations, never prompt
    #[arg(short = 'f', long)]
    force: bool,

    /// Use 'git mv' instead of rename
    #[arg(short = 'g', long)]
    git: bool,

    /// Prompt before overwrite
    #[arg(short = 'i', long)]
    interactive: bool,

    /// Hard link files instead of rename
    #[arg(short = 'l', long = "link-only")]
    link_only: bool,

    /// Don't rename, implies --verbose
    #[arg(short = 'n', long = "just-print", alias = "dry-run")]
    dry_run: bool,

    /// Read filenames from standard input
    #[arg(short = 's', long)]
    stdin: bool,

    /// Explain what is being done
    #[arg(short = 'v', long)]
    verbose: bool,

    /// Set backup method
    #[arg(short = 'V', long = "version-control", value_enum)]
    version_control: Option<VersionControl>,

    /// Set backup file basename prefix
    #[arg(short = 'Y', long = "basename-prefix", value_name = "PREFIX")]
    basename_prefix: Option<String>,

    /// Set backup filename suffix
    #[arg(short = 'z', short = 'S', long = "suffix", value_name = "SUFFIX")]
    suffix: Option<String>,



    /// Process files in parallel
    #[arg(short = 'j', long, value_name = "JOBS")]
    jobs: Option<usize>,

    /// Continue on errors
    #[arg(long)]
    continue_on_error: bool,

    /// Use case-insensitive matching
    #[arg(long)]
    ignore_case: bool,

    /// Regular expression pattern to match
    pattern: Option<String>,

    /// Replacement string (can include capture groups like $1, $2, etc.)
    replacement: Option<String>,

    /// Files to rename
    files: Vec<String>,
}

#[derive(Debug, Clone)]
enum VcmType {
    Off,
    Simple,
    Test,
    Numbered,
}

#[derive(Debug, Clone)]
struct RenameConfig {
    backup: bool,
    copy: bool,
    command: Option<String>,
    prefix: String,
    force: bool,
    interactive: bool,
    link_only: bool,
    dry_run: bool,
    verbose: bool,
    vcm: VcmType,
    basename_prefix: String,
    suffix: String,
    pattern: Regex,
    replacement: String,
    jobs: usize,
    continue_on_error: bool,
}

impl RenameConfig {
    fn new(args: Args) -> Result<Self> {
        let mut command = args.command;
        
        if args.git {
            command = Some("git mv".to_string());
        }

        // Validate incompatible options
        if let Some(ref cmd) = command {
            if args.backup {
                bail!(RenameError::IncompatibleOptions {
                    message: "--backup is incompatible with --command".to_string()
                });
            }
            
            let placeholder_count = cmd.matches("{}").count();
            if placeholder_count == 0 {
                command = Some(format!("{} {{}} {{}}", cmd));
            } else if placeholder_count != 2 {
                bail!(RenameError::IncompatibleOptions {
                    message: "command needs exactly 0 or 2 of {} for parameter substitution".to_string()
                });
            }
        }

        if args.copy && args.link_only {
            bail!(RenameError::IncompatibleOptions {
                message: "cannot both copy and link".to_string()
            });
        }

        // Determine version control method
        let vcm = if args.backup {
            if args.prefix.is_some() || args.basename_prefix.is_some() || args.suffix.is_some() {
                VcmType::Simple
            } else {
                match args.version_control.unwrap_or(VersionControl::Existing) {
                    VersionControl::None | VersionControl::Off => VcmType::Off,
                    VersionControl::Nil | VersionControl::Existing => VcmType::Test,
                    VersionControl::Numbered | VersionControl::T => VcmType::Numbered,
                    VersionControl::Never | VersionControl::Simple => VcmType::Simple,
                }
            }
        } else {
            VcmType::Off
        };

        let backup = !matches!(vcm, VcmType::Off) && args.backup;

        let suffix = args.suffix.unwrap_or_else(|| {
            env::var("SIMPLE_BACKUP_SUFFIX").unwrap_or_else(|_| "~".to_string())
        });

        // Build the regex pattern
        let pattern = match args.pattern {
            Some(p) => {
                let mut builder = regex::RegexBuilder::new(&p);
                builder.case_insensitive(args.ignore_case);
                builder.build()?
            }
            None => bail!("missing pattern argument"),
        };

        let replacement = args.replacement.unwrap_or_else(|| {
            eprintln!("error: missing replacement argument");
            exit(1);
        });

        Ok(RenameConfig {
            backup,
            copy: args.copy,
            command,
            prefix: args.prefix.unwrap_or_default(),
            force: args.force,
            interactive: args.interactive,
            link_only: args.link_only,
            dry_run: args.dry_run,
            verbose: args.verbose || args.dry_run,
            vcm,
            basename_prefix: args.basename_prefix.unwrap_or_default(),
            suffix,
            pattern,
            replacement,
            jobs: args.jobs.unwrap_or_else(|| num_cpus::get()),
            continue_on_error: args.continue_on_error,
        })
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    let args = Args::parse();

    let config = RenameConfig::new(args.clone())
        .context("Failed to create configuration")?;

    let mut files = args.files;
    
    if files.is_empty() && args.stdin {
        files = read_files_from_stdin().await?;
    }

    if files.is_empty() {
        return Ok(());
    }

    // Set up signal handling
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.ok();
        r.store(false, Ordering::SeqCst);
    });

    // Process files
    if config.jobs == 1 {
        process_files_sequential(&files, &config, &running).await?;
    } else {
        process_files_parallel(&files, &config, &running).await?;
    }

    Ok(())
}

async fn read_files_from_stdin() -> Result<Vec<String>> {
    let stdin = tokio::io::stdin();
    let reader = AsyncBufReader::new(stdin);
    let mut lines = reader.lines();
    let mut files = Vec::new();
    
    while let Some(line) = lines.next_line().await? {
        files.push(line);
    }
    
    Ok(files)
}

async fn process_files_sequential(
    files: &[String], 
    config: &RenameConfig, 
    running: &Arc<AtomicBool>
) -> Result<()> {
    let mut errors = Vec::new();
    
    for file in files {
        if !running.load(Ordering::SeqCst) {
            break;
        }
        
        if let Err(e) = process_file(file, config).await {
            error!("Failed to process {}: {}", file, e);
            errors.push(e);
            
            if !config.continue_on_error {
                break;
            }
        }
    }
    
    if !errors.is_empty() && !config.continue_on_error {
        bail!("Processing stopped due to errors");
    }
    
    Ok(())
}

async fn process_files_parallel(
    files: &[String], 
    config: &RenameConfig, 
    running: &Arc<AtomicBool>
) -> Result<()> {
    use tokio::sync::Semaphore;
    use futures::future::join_all;
    
    let semaphore = Arc::new(Semaphore::new(config.jobs));
    let config = Arc::new(config.clone());
    
    let tasks: Vec<_> = files.iter().map(|file| {
        let file = file.clone();
        let config = config.clone();
        let semaphore = semaphore.clone();
        let running = running.clone();
        
        tokio::spawn(async move {
            let _permit = semaphore.acquire().await.unwrap();
            
            if !running.load(Ordering::SeqCst) {
                return Ok(());
            }
            
            process_file(&file, &config).await
        })
    }).collect();
    
    let results = join_all(tasks).await;
    let mut errors = Vec::new();
    
    for result in results {
        match result {
            Ok(Ok(())) => {}
            Ok(Err(e)) => {
                error!("File processing error: {}", e);
                errors.push(e);
            }
            Err(e) => {
                error!("Task join error: {}", e);
            }
        }
    }
    
    if !errors.is_empty() && !config.continue_on_error {
        bail!("Processing completed with {} errors", errors.len());
    }
    
    Ok(())
}

async fn process_file(file: &str, config: &RenameConfig) -> Result<()> {
    let new_name = config.pattern.replace_all(file, &config.replacement);
    
    if new_name == file {
        debug!("No change needed for {}", file);
        return Ok(());
    }

    let new_name = new_name.to_string();

    // Check for null bytes (security check)
    if new_name.contains('\0') {
        warn!("Skipping {} -> {} due to null byte", file, new_name);
        return Err(RenameError::NullByteInFilename { 
            filename: new_name 
        }.into());
    }

    let new_path = Path::new(&new_name);
    
    if new_path.exists() && !config.force {
        if !is_writable(new_path).await && is_interactive() {
            if !prompt_user(&format!("overwrite `{}`, overriding mode?", new_name)).await? {
                return Ok(());
            }
        } else if config.interactive {
            if !prompt_user(&format!("replace `{}`?", new_name)).await? {
                return Ok(());
            }
        }
    }

    // Handle backup
    if config.backup && new_path.exists() {
        let backup_path = create_backup_name(&new_name, config).await?;
        
        if config.verbose {
            info!("backup: {} -> {}", new_name, backup_path);
        }
        
        if !config.dry_run {
            if let Some(parent) = Path::new(&backup_path).parent() {
                async_fs::create_dir_all(parent).await?;
            }
            async_fs::rename(&new_name, &backup_path).await
                .map_err(|e| RenameError::BackupFailed { 
                    file: new_name.clone(), 
                    source: e 
                })?;
        }
    }

    // Create parent directories if needed
    if let Some(parent) = new_path.parent() {
        if !parent.exists() {
            if config.verbose {
                info!("mkdir: {}", parent.display());
            }
            if !config.dry_run {
                async_fs::create_dir_all(parent).await?;
            }
        }
    }

    // Show what we're doing
    if config.verbose {
        if let Some(ref cmd) = config.command {
            info!("exec: {}", cmd.replace("{}", file).replacen("{}", &new_name, 1));
        } else {
            let op = if config.link_only { "=" } else { "-" };
            info!("{} {}> {}", file, op, new_name);
        }
    }

    if config.dry_run {
        return Ok(());
    }

    // Perform the actual operation
    if let Some(ref command) = config.command {
        execute_command(command, file, &new_name).await?;
    } else if config.link_only {
        async_fs::hard_link(file, &new_name).await?;
    } else if config.copy {
        async_fs::copy(file, &new_name).await?;
    } else {
        async_fs::rename(file, &new_name).await?;
    }

    Ok(())
}

async fn execute_command(command: &str, from: &str, to: &str) -> Result<()> {
    let cmd = command.replace("{}", from).replacen("{}", to, 1);
    
    let output = Command::new("sh")
        .arg("-c")
        .arg(&cmd)
        .output()
        .context("Failed to execute command")?;
    
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        error!("Command failed: {}, stderr: {}", cmd, stderr);
        return Err(RenameError::CommandFailed { command: cmd }.into());
    }
    
    Ok(())
}

async fn create_backup_name(filename: &str, config: &RenameConfig) -> Result<String> {
    match config.vcm {
        VcmType::Simple => {
            let path = Path::new(filename);
            let parent = path.parent().unwrap_or(Path::new(""));
            let basename = path.file_name().unwrap().to_str().unwrap();
            
            Ok(format!("{}{}{}{}", 
                config.prefix,
                parent.display(),
                if !parent.as_os_str().is_empty() { "/" } else { "" },
                format!("{}{}{}", config.basename_prefix, basename, config.suffix)
            ))
        }
        VcmType::Numbered | VcmType::Test => {
            let pattern = format!("{}.~*~", filename);
            let mut existing_backups: Vec<_> = glob(&pattern)?
                .filter_map(|entry| entry.ok())
                .collect();
            
            existing_backups.sort_by(|a, b| {
                let a_num = extract_backup_number(a);
                let b_num = extract_backup_number(b);
                b_num.cmp(&a_num)
            });

            let next_num = if let Some(highest) = existing_backups.first() {
                extract_backup_number(highest) + 1
            } else if matches!(config.vcm, VcmType::Test) {
                // For "test" mode, fall back to simple backup if no numbered backups exist
                let path = Path::new(filename);
                let parent = path.parent().unwrap_or(Path::new(""));
                let basename = path.file_name().unwrap().to_str().unwrap();
                
                return Ok(format!("{}{}{}{}", 
                    config.prefix,
                    parent.display(),
                    if !parent.as_os_str().is_empty() { "/" } else { "" },
                    format!("{}{}{}", config.basename_prefix, basename, config.suffix)
                ));
            } else {
                1
            };

            Ok(format!("{}.~{}~", filename, next_num))
        }
        VcmType::Off => unreachable!(),
    }
}

fn extract_backup_number(path: &Path) -> u32 {
    let filename = path.file_name().unwrap().to_str().unwrap();
    let re = Regex::new(r"\.~(\d+)~$").unwrap();
    
    if let Some(caps) = re.captures(filename) {
        caps[1].parse().unwrap_or(0)
    } else {
        0
    }
}

async fn is_writable(path: &Path) -> bool {
    async_fs::metadata(path)
        .await
        .map(|m| !m.permissions().readonly())
        .unwrap_or(false)
}

fn is_interactive() -> bool {
    atty::is(atty::Stream::Stdin)
}

async fn prompt_user(message: &str) -> Result<bool> {
    print!("rename: {}? ", message);
    io::stdout().flush()?;
    
    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    
    Ok(input.trim().to_lowercase().starts_with('y'))
}