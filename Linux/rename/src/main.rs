use std::env;
use std::fs;
use std::io::{self, Write, BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use clap::{Parser, ValueEnum};
use regex::Regex;
use glob::glob;

const VERSION: &str = "2.0.0";

#[derive(Debug, Clone, ValueEnum)]
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
    #[arg(short = 's', long, default_value = "true")]
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

    /// Generate shell completion code
    #[arg(long, value_name = "SHELL")]
    shell_completion: Option<String>,

    /// Regular expression pattern to match
    pattern: Option<String>,

    /// Replacement string (can include capture groups like $1, $2, etc.)
    replacement: Option<String>,

    /// Files to rename
    files: Vec<String>,
}

#[derive(Debug)]
enum VcmType {
    Off,
    Simple,
    Test,
    Numbered,
}

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
}

impl RenameConfig {
    fn new(args: Args) -> Result<Self, Box<dyn std::error::Error>> {
        let mut command = args.command;
        
        if args.git {
            command = Some("git mv".to_string());
        }

        // Handle command parameter formatting
        if let Some(ref cmd) = command {
            if args.backup {
                eprintln!("error: --backup is incompatible with --command");
                exit(1);
            }
            
            let placeholder_count = cmd.matches("{}").count();
            if placeholder_count == 0 {
                command = Some(format!("{} {{}} {{}}", cmd));
            } else if placeholder_count != 2 {
                eprintln!("error: command needs exactly 0 or 2 of {{}} for parameter substitution");
                exit(1);
            }
        }

        if args.copy && args.link_only {
            eprintln!("error: cannot both copy and link");
            exit(1);
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

        let backup = match vcm {
            VcmType::Off => false,
            _ => args.backup,
        };

        let suffix = args.suffix.unwrap_or_else(|| {
            env::var("SIMPLE_BACKUP_SUFFIX").unwrap_or_else(|_| "~".to_string())
        });

        // Build the regex pattern
        let pattern = match args.pattern {
            Some(p) => Regex::new(&p)?,
            None => {
                eprintln!("error: missing pattern argument");
                exit(1);
            }
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
        })
    }
}

fn main() {
    let args = Args::parse();

    if let Some(shell) = args.shell_completion {
        generate_shell_completion(&shell);
        return;
    }

    let config = match RenameConfig::new(args.clone()) {
        Ok(config) => config,
        Err(e) => {
            eprintln!("error: {}", e);
            exit(1);
        }
    };

    let mut files = args.files;
    
    if files.is_empty() && args.stdin {
        let stdin = io::stdin();
        let reader = BufReader::new(stdin.lock());
        files = reader.lines()
            .filter_map(|line| line.ok())
            .collect();
    }

    if files.is_empty() {
        exit(0);
    }

    for file in files {
        if let Err(e) = process_file(&file, &config) {
            eprintln!("rename: {}", e);
        }
    }
}

fn process_file(file: &str, config: &RenameConfig) -> Result<(), Box<dyn std::error::Error>> {
    let new_name = config.pattern.replace_all(file, &config.replacement);
    
    if new_name == file {
        return Ok(());
    }

    let new_name = new_name.to_string();

    // Check for null bytes (security check)
    if new_name.contains('\0') {
        eprintln!("rename: `{}` -> `{}`, skipping due to null byte", file, new_name);
        return Ok(());
    }

    let new_path = Path::new(&new_name);
    
    if new_path.exists() && !config.force {
        if !is_writable(new_path) && atty::is(atty::Stream::Stdin) {
            print!("rename: overwrite `{}`, overriding mode? ", new_name);
            io::stdout().flush()?;
            let mut input = String::new();
            io::stdin().read_line(&mut input)?;
            if !input.trim().to_lowercase().starts_with('y') {
                return Ok(());
            }
        } else if config.interactive {
            print!("rename: replace `{}`? ", new_name);
            io::stdout().flush()?;
            let mut input = String::new();
            io::stdin().read_line(&mut input)?;
            if !input.trim().to_lowercase().starts_with('y') {
                return Ok(());
            }
        }
    }

    // Handle backup
    if config.backup && new_path.exists() {
        let backup_path = create_backup_name(&new_name, &config)?;
        
        if config.verbose && config.dry_run {
            println!("backup: {} -> {}", new_name, backup_path);
        }
        
        if !config.dry_run {
            if let Some(parent) = Path::new(&backup_path).parent() {
                fs::create_dir_all(parent)?;
            }
            fs::rename(&new_name, &backup_path)?;
        }
    }

    // Create parent directories if needed
    if let Some(parent) = new_path.parent() {
        if !parent.exists() {
            if config.dry_run && config.verbose {
                println!("mkdir: {}", parent.display());
            } else if !config.dry_run {
                fs::create_dir_all(parent)?;
            }
        }
    }

    // Show what we're doing
    if config.dry_run || config.verbose {
        if let Some(ref cmd) = config.command {
            println!("exec: {}", cmd.replace("{}", file).replacen("{}", &new_name, 1));
        } else {
            let op = if config.link_only { "=" } else { "-" };
            println!("{} {}> {}", file, op, new_name);
        }
    }

    if config.dry_run {
        return Ok(());
    }

    // Perform the actual operation
    if let Some(ref command) = config.command {
        let cmd = command.replace("{}", file).replacen("{}", &new_name, 1);
        let output = Command::new("sh")
            .arg("-c")
            .arg(&cmd)
            .output()?;
        
        if !output.status.success() {
            eprintln!("rename: error running `{}`: {}", cmd, 
                String::from_utf8_lossy(&output.stderr));
        }
    } else if config.link_only {
        fs::hard_link(file, &new_name)?;
    } else if config.copy {
        fs::copy(file, &new_name)?;
    } else {
        fs::rename(file, &new_name)?;
    }

    Ok(())
}

fn create_backup_name(filename: &str, config: &RenameConfig) -> Result<String, Box<dyn std::error::Error>> {
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
            } else if config.vcm == VcmType::Test {
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

fn is_writable(path: &Path) -> bool {
    path.metadata()
        .map(|m| !m.permissions().readonly())
        .unwrap_or(false)
}

fn generate_shell_completion(shell: &str) {
    match shell {
        "bash" => {
            println!("complete -F _comp_rename rename;");
            println!("_comp_rename() {{");
            println!("    COMPREPLY=($(compgen -W \"--backup --copy --command --prefix --force --git --help --interactive --link-only --just-print --dry-run --stdin --no-stdin --verbose --version-control --basename-prefix --suffix --shell-completion --version\" -- \"${{COMP_WORDS[$COMP_CWORD]}}\"));");
            println!("}};");
        }
        "zsh" => {
            println!("compdef _comp_rename rename;");
            println!("_comp_rename() {{");
            println!("    _arguments -S -s \\");
            println!("        '(-b --backup){{-b,--backup}}[make backup before removal]' \\");
            println!("        '(-c --copy){{-c,--copy}}[copy file instead of rename]' \\");
            println!("        '(-C --command){{-C,--command}}[use COMMAND instead of rename]:command:' \\");
            println!("        '(-B --prefix){{-B,--prefix}}[set backup filename prefix]:prefix:' \\");
            println!("        '(-f --force){{-f,--force}}[remove existing destinations, never prompt]' \\");
            println!("        '(-g --git){{-g,--git}}[use git mv instead of rename]' \\");
            println!("        '(-i --interactive){{-i,--interactive}}[prompt before overwrite]' \\");
            println!("        '(-l --link-only){{-l,--link-only}}[hard link files instead of rename]' \\");
            println!("        '(-n --just-print --dry-run){{-n,--just-print,--dry-run}}[don\\'t rename, implies --verbose]' \\");
            println!("        '(-s --stdin --no-stdin){{-s,--stdin,--no-stdin}}[read filenames from standard input]' \\");
            println!("        '(-v --verbose){{-v,--verbose}}[explain what is being done]' \\");
            println!("        '(-V --version-control){{-V,--version-control}}[set backup method]:method:(none off nil existing numbered t never simple)' \\");
            println!("        '(-Y --basename-prefix){{-Y,--basename-prefix}}[set backup file basename prefix]:prefix:' \\");
            println!("        '(-z -S --suffix){{-z,-S,--suffix}}[set backup filename suffix]:suffix:' \\");
            println!("        '1:pattern:' \\");
            println!("        '2:replacement:' \\");
            println!("        '*:files:_files';");
            println!("}};");
        }
        _ => {
            eprintln!("No completion support for `{}`", shell);
            exit(1);
        }
    }
}