#!/usr/bin/env bash
# bash <(curl -qfsSL 'https://github.com/pkgforge/devscripts/raw/refs/heads/main/Linux/extraxtor.sh')
# extraxtor - Archive Extractor with Intelligent Directory Flattening
# Usage: extraxtor <input_archive> <output_dir>

# Configuration
declare -g INPUT_FILE="" OUTPUT_DIR=""
declare -g VERBOSE=false QUIET=false FORCE=false FLATTEN=true TREE_OUTPUT=false
declare -g TEMP_DIR="" ORIGINAL_DIR="" CLEANUP_REQUIRED=false

if [[ -t 1 ]]; then
    declare -gr RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' 
    declare -gr BLUE='\033[0;34m' MAGENTA='\033[0;35m' CYAN='\033[0;36m' RESET='\033[0m'
else
    declare -gr RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' RESET=''
fi

# Cleanup function
cleanup() {
    local exit_code=$?
    
    if [[ $CLEANUP_REQUIRED == true ]]; then
        log_debug "Performing cleanup..."
        
        # Return to original directory if we changed it
        if [[ -n $ORIGINAL_DIR && $ORIGINAL_DIR != "$PWD" ]]; then
            if cd "$ORIGINAL_DIR" 2>/dev/null; then
                log_debug "Returned to original directory: $ORIGINAL_DIR"
            else
                log_warn "Failed to return to original directory: $ORIGINAL_DIR"
            fi
        fi
        
        # Clean up temporary files and directories
        if [[ -n $TEMP_DIR && -d $TEMP_DIR ]]; then
            if rm -rf "$TEMP_DIR" 2>/dev/null; then
                log_debug "Cleaned up temporary directory: $TEMP_DIR"
            else
                log_warn "Failed to clean up temporary directory: $TEMP_DIR"
            fi
        fi
        
        # Clean up any .tmp_flatten_* directories in current directory
        for temp_flatten in .tmp_flatten_*; do
            if [[ -d $temp_flatten ]]; then
                if rm -rf "$temp_flatten" 2>/dev/null; then
                    log_debug "Cleaned up flatten temp directory: $temp_flatten"
                else
                    log_warn "Failed to clean up flatten temp directory: $temp_flatten"
                fi
            fi
        done
        
        CLEANUP_REQUIRED=false
    fi
    
    # Exit with original exit code if non-zero, otherwise exit cleanly
    if [[ $exit_code -ne 0 ]]; then
        log_debug "Exiting with code: $exit_code"
        exit $exit_code
    fi
}

# Set up traps for cleanup
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 1' ERR

# Logging functions
log_error() { 
    if [[ $QUIET != true ]]; then
        echo -e "${RED}[ERROR]${RESET} $*" >&2
    fi
    return 0
}

log_warn() { 
    if [[ $QUIET != true ]]; then
        echo -e "${YELLOW}[WARN]${RESET} $*" >&2
    fi
    return 0
}

log_info() { 
    if [[ $QUIET != true ]]; then
        echo -e "${GREEN}[INFO]${RESET} $*"
    fi
    return 0
}

log_debug() { 
    if [[ $VERBOSE == true ]]; then
        echo -e "${BLUE}[DEBUG]${RESET} $*"
    fi
    return 0
}

log_success() { 
    if [[ $QUIET != true ]]; then
        echo -e "${GREEN}[SUCCESS]${RESET} $*"
    fi
    return 0
}

show_help() {
    cat << 'EOF'
Archive Extractor with Intelligent Directory Flattening
USAGE:
    extraxtor [OPTIONS] <archive_file> [output_directory]
OPTIONS:
    -i, --input FILE    Input archive file
    -o, --output DIR    Output directory (default: current dir)
    -f, --force         Force extraction, overwrite existing files
    -q, --quiet         Suppress all output except errors
    -v, --verbose       Enable verbose output
    -n, --no-flatten    Don't flatten nested single directories
    -t, --tree          Show tree output after extraction
    -h, --help          Show this help message
SUPPORTED FORMATS:
    tar, tar.gz, tgz, tar.bz2, tbz2, tar.xz, txz, zip, 7z, rar, gz, bz2, xz
EXAMPLES:
    extraxtor archive.tar.gz /tmp/extract
    extraxtor -i package.zip -o ./output --verbose --tree
    extraxtor --quiet --force archive.7z
EOF
    return 0
}

# Dependency check with realpath validation
check_dependencies() {
    local missing=()
    local tool=""
    
    for tool in file tar realpath; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        return 1
    fi
    
    # Optional tool warnings
    local cmd="" fmt=""
    for tool in unzip:ZIP 7z:7Z unrar:RAR tree:TREE; do
        if [[ $tool == *:* ]]; then
            cmd="${tool%:*}"
            fmt="${tool#*:}"
            if ! command -v "$cmd" &>/dev/null; then
                log_debug "$fmt support unavailable - $cmd not found"
            fi
        fi
    done
    
    return 0
}

# Enhanced path resolution with symlink handling
resolve_path() {
    local path="$1"
    local resolved_path=""
    
    if [[ -z $path ]]; then
        echo ""
        return 1
    fi
    
    # Try realpath first (most reliable)
    if command -v realpath &>/dev/null; then
        resolved_path="$(realpath "$path" 2>/dev/null)"
        if [[ -n $resolved_path ]]; then
            echo "$resolved_path"
            return 0
        fi
    fi
    
    # Fallback to readlink for symlinks
    if [[ -L "$path" ]] && command -v readlink &>/dev/null; then
        resolved_path="$(readlink -f "$path" 2>/dev/null)"
        if [[ -n $resolved_path ]]; then
            echo "$resolved_path"
            return 0
        fi
    fi
    
    # Final fallback - basic path resolution
    if [[ -e "$path" ]]; then
        local dir_path=""
        local base_name=""
        
        dir_path="$(dirname "$path")"
        base_name="$(basename "$path")"
        
        if cd "$dir_path" 2>/dev/null; then
            resolved_path="$PWD/$base_name"
            cd - >/dev/null 2>&1 || true
            echo "$resolved_path"
            return 0
        fi
    fi
    
    # Return original path if all else fails
    echo "$path"
    return 1
}

# Archive type detection (improved pattern matching)
detect_archive_type() {
    local file_path="$1"
    local mime_type="${2:-}"
    local file_output=""
    local ext=""
    
    if [[ -z $file_path ]]; then
        log_error "No file path provided for detection"
        return 1
    fi
    
    ext="${file_path##*.}"
    ext="${ext,,}"
    
    if ! file_output="$(file -b "$file_path" 2>/dev/null)" || [[ -z $file_output ]]; then
        log_error "Cannot determine file type: $file_path"
        return 1
    fi
    
    if [[ -z $mime_type ]]; then
        if ! mime_type="$(file -b --mime-type "$file_path" 2>/dev/null)"; then
            mime_type="unknown"
        fi
    fi
    
    log_debug "File: $file_output | MIME: $mime_type | Ext: $ext"
    
    # Improved pattern matching
    case "$file_output" in
        *"gzip compressed"*)
            case "$ext" in
                gz) 
                    if [[ $file_output == *"tar archive"* ]]; then
                        echo "tar.gz"
                    else
                        echo "gzip"
                    fi
                    ;;
                tgz|tar.gz) echo "tar.gz" ;;
                *) echo "tar.gz" ;;
            esac 
            ;;
        *"bzip2 compressed"*)
            case "$ext" in
                tar.bz2|tbz2) echo "tar.bz2" ;;
                *) echo "bzip2" ;;
            esac
            ;;
        *"XZ compressed"*)
            case "$ext" in
                tar.xz|txz) echo "tar.xz" ;;
                *) echo "xz" ;;
            esac
            ;;
        *"Zip archive"*|*"ZIP archive"*) echo "zip" ;;
        *"7-zip archive"*) echo "7z" ;;
        *"RAR archive"*) echo "rar" ;;
        *"POSIX tar archive"*|*"tar archive"*)
            if [[ $ext == "tar" ]]; then
                echo "tar"
            else
                echo "tar.gz"
            fi
            ;;
        *)
            case "$ext" in
                tar) echo "tar" ;;
                tar.gz|tgz) echo "tar.gz" ;;
                tar.bz2|tbz2) echo "tar.bz2" ;;
                tar.xz|txz) echo "tar.xz" ;;
                gz) echo "gzip" ;;
                bz2) echo "bzip2" ;;
                xz) echo "xz" ;;
                zip|jar|war|ear) echo "zip" ;;
                7z) echo "7z" ;;
                rar) echo "rar" ;;
                *) 
                    log_error "Unsupported format: $file_path"
                    return 1
                    ;;
            esac 
            ;;
    esac
    
    return 0
}

# Archive validation (enhanced with redundancy)
validate_archive() {
    local file_path="$1"
    local archive_type="$2"
    local validation_cmd=""
    local result=0
    
    if [[ -z $file_path || -z $archive_type ]]; then
        log_error "Missing parameters for archive validation"
        return 1
    fi
    
    log_debug "Validating $archive_type: $file_path"
    
    # Define validation commands
    case "$archive_type" in
        tar) validation_cmd="tar -tf" ;;
        tar.gz) validation_cmd="tar -tzf" ;;
        tar.bz2) validation_cmd="tar -tjf" ;;
        tar.xz) validation_cmd="tar -tJf" ;;
        zip) 
            if command -v unzip &>/dev/null; then
                validation_cmd="unzip -t"
            else
                log_warn "Cannot validate ZIP - unzip unavailable"
                return 0
            fi
            ;;
        7z) 
            if command -v 7z &>/dev/null; then
                validation_cmd="7z t"
            elif command -v 7za &>/dev/null; then
                validation_cmd="7za t"
            else
                log_warn "Cannot validate 7Z - 7z/7za unavailable"
                return 0
            fi
            ;;
        rar) 
            if command -v unrar &>/dev/null; then
                validation_cmd="unrar t"
            else
                log_warn "Cannot validate RAR - unrar unavailable"
                return 0
            fi
            ;;
        gzip) validation_cmd="gzip -t" ;;
        bzip2) validation_cmd="bzip2 -t" ;;
        xz) validation_cmd="xz -t" ;;
        *)
            log_warn "No validation method for: $archive_type"
            return 0
            ;;
    esac
    
    if [[ -n $validation_cmd ]]; then
        $validation_cmd "$file_path" &>/dev/null
        result=$?
        if [[ $result -ne 0 ]]; then
            log_error "Archive validation failed: $file_path"
            return 1
        fi
    fi
    
    return 0
}

# Extract archive
extract_archive() {
    local file_path="$1"
    local output_dir="$2"
    local archive_type="$3"
    local original_dir="$PWD"
    local output_file=""
    local base_name=""
    local result=0
    
    if [[ -z $file_path || -z $output_dir || -z $archive_type ]]; then
        log_error "Missing parameters for extraction"
        return 1
    fi
    
    ORIGINAL_DIR="$original_dir"
    CLEANUP_REQUIRED=true
    
    log_info "Extracting ${CYAN}$archive_type${RESET}: ${YELLOW}${file_path##*/}${RESET}"
    
    if ! mkdir -p "$output_dir" 2>/dev/null; then
        log_error "Failed to create directory: $output_dir"
        return 1
    fi
    
    if ! cd "$output_dir" 2>/dev/null; then
        log_error "Failed to access directory: $output_dir"
        return 1
    fi
    
    # Enhanced extraction with proper error handling
    case "$archive_type" in
        tar) 
            tar -xf "$file_path"
            result=$?
            ;;
        tar.gz) 
            tar -xzf "$file_path"
            result=$?
            ;;
        tar.bz2) 
            tar -xjf "$file_path"
            result=$?
            ;;
        tar.xz) 
            tar -xJf "$file_path"
            result=$?
            ;;
        zip)
            if command -v unzip &>/dev/null; then
                if [[ $VERBOSE == true ]]; then
                    unzip -o "$file_path"
                else
                    unzip -oq "$file_path"
                fi
                result=$?
            else
                log_error "unzip unavailable"
                cd "$original_dir" 2>/dev/null || true
                return 1
            fi
            ;;
        7z)
            if command -v 7z &>/dev/null; then
                if [[ $VERBOSE == true ]]; then
                    7z x "$file_path" -y
                else
                    7z x "$file_path" -y &>/dev/null
                fi
                result=$?
            elif command -v 7za &>/dev/null; then
                if [[ $VERBOSE == true ]]; then
                    7za x "$file_path" -y
                else
                    7za x "$file_path" -y &>/dev/null
                fi
                result=$?
            else
                log_error "7z/7za unavailable"
                cd "$original_dir" 2>/dev/null || true
                return 1
            fi
            ;;
        rar)
            if command -v unrar &>/dev/null; then
                if [[ $VERBOSE == true ]]; then
                    unrar x "$file_path" -y
                else
                    unrar x "$file_path" -y &>/dev/null
                fi
                result=$?
            else
                log_error "unrar unavailable"
                cd "$original_dir" 2>/dev/null || true
                return 1
            fi
            ;;
        gzip|bzip2|xz)
            base_name="${file_path##*/}"
            case "$archive_type" in
                gzip) 
                    output_file="${base_name%.gz}"
                    gzip -dc "$file_path" > "$output_file"
                    result=$?
                    ;;
                bzip2) 
                    output_file="${base_name%.bz2}"
                    bzip2 -dc "$file_path" > "$output_file"
                    result=$?
                    ;;
                xz) 
                    output_file="${base_name%.xz}"
                    xz -dc "$file_path" > "$output_file"
                    result=$?
                    ;;
            esac
            ;;
        *) 
            log_error "Unsupported archive type: $archive_type"
            cd "$original_dir" 2>/dev/null || true
            return 1
            ;;
    esac
    
    if ! cd "$original_dir" 2>/dev/null; then
        log_warn "Failed to return to original directory: $original_dir"
    fi
    
    if [[ $result -ne 0 ]]; then
        log_error "Extraction failed with exit code: $result"
        return 1
    fi
    
    return 0
}

# Enhanced directory flattening with better logic
flatten_directories() {
    local target_dir="$1"
    local original_dir="$PWD"
    local flattened=0
    local temp_dir=""
    local items=()
    local hidden_items=()
    local all_items=()
    local item=""
    local source_dir=""
    local move_result=0
    
    if [[ -z $target_dir ]]; then
        log_error "No target directory specified for flattening"
        return 1
    fi
    
    if [[ $FLATTEN != true ]]; then
        log_debug "Flattening disabled"
        return 0
    fi
    
    ORIGINAL_DIR="$original_dir"
    CLEANUP_REQUIRED=true
    
    if ! cd "$target_dir" 2>/dev/null; then
        log_error "Cannot access directory: $target_dir"
        return 1
    fi
    
    while true; do
        items=(*)
        hidden_items=(.*)
        all_items=()
        
        # Combine visible and hidden items (excluding . and ..)
        for item in "${items[@]}"; do
            if [[ $item != "*" ]]; then
                all_items+=("$item")
            fi
        done
        
        for item in "${hidden_items[@]}"; do
            if [[ $item != ".*" && $item != "." && $item != ".." ]]; then
                all_items+=("$item")
            fi
        done
        
        # If exactly one directory, flatten it
        if [[ ${#all_items[@]} -eq 1 && -d ${all_items[0]} ]]; then
            source_dir="${all_items[0]}"
            
            # Check if directory has contents
            if [[ -n $(ls -A "$source_dir" 2>/dev/null) ]]; then
                log_info "Flattening: ${MAGENTA}$source_dir${RESET}"
                
                temp_dir=".tmp_flatten_$$"
                if ! mkdir "$temp_dir" 2>/dev/null; then
                    log_warn "Failed to create temporary directory for flattening"
                    break
                fi
                
                TEMP_DIR="$temp_dir"
                
                # Move all contents (including hidden files)
                (
                    shopt -s dotglob 2>/dev/null || true
                    mv "$source_dir"/* "$temp_dir"/ 2>/dev/null
                )
                move_result=$?
                
                if [[ $move_result -eq 0 ]]; then
                    if rmdir "$source_dir" 2>/dev/null; then
                        (
                            shopt -s dotglob 2>/dev/null || true
                            mv "$temp_dir"/* . 2>/dev/null
                        )
                        move_result=$?
                        
                        if [[ $move_result -eq 0 ]]; then
                            if rmdir "$temp_dir" 2>/dev/null; then
                                flattened=$((flattened + 1))
                                TEMP_DIR=""
                            else
                                log_warn "Failed to remove temporary directory: $temp_dir"
                            fi
                        else
                            log_warn "Failed to move contents from temporary directory"
                            break
                        fi
                    else
                        log_warn "Failed to remove source directory: $source_dir"
                        break
                    fi
                else
                    log_warn "Failed to flatten directory: $source_dir"
                    if rmdir "$temp_dir" 2>/dev/null; then
                        TEMP_DIR=""
                    fi
                    break
                fi
            else
                if rmdir "$source_dir" 2>/dev/null; then
                    log_debug "Removed empty directory: $source_dir"
                fi
                break
            fi
        else
            break
        fi
    done
    
    if ! cd "$original_dir" 2>/dev/null; then
        log_warn "Failed to return to original directory: $original_dir"
    fi
    
    if [[ $flattened -gt 0 ]]; then
        local directory_word="directories"
        if [[ $flattened -eq 1 ]]; then
            directory_word="directory"
        fi
        log_success "Flattened $flattened $directory_word"
    fi
    
    return 0
}

# Show results with optional tree output
show_results() {
    local output_dir="$1"
    local item_count=""
    
    if [[ -z $output_dir ]]; then
        log_error "No output directory specified for results"
        return 1
    fi
    
    if command -v find &>/dev/null; then
        item_count=$(find "$output_dir" -mindepth 1 2>/dev/null | wc -l)
        if [[ $? -eq 0 && -n $item_count ]]; then
            log_success "Extracted $item_count items to: ${CYAN}$output_dir${RESET}"
        else
            log_success "Extraction complete: ${CYAN}$output_dir${RESET}"
        fi
    else
        log_success "Extraction complete: ${CYAN}$output_dir${RESET}"
    fi
    
    if [[ $TREE_OUTPUT == true ]] && command -v tree &>/dev/null; then
        log_info "Directory structure:"
        if ! tree -L 3 "$output_dir" 2>/dev/null; then
            ls -la "$output_dir" 2>/dev/null || log_warn "Failed to list directory contents"
        fi
    elif [[ $VERBOSE == true ]]; then
        log_info "Contents:"
        if ! ls -la "$output_dir" 2>/dev/null; then
            log_warn "Failed to list directory contents"
        fi
    fi
    
    return 0
}

# Main extraction function
extract_main() {
    local input_file=""
    local output_dir=""
    local archive_type=""
    local resolved_input=""
    local resolved_output=""
    
    if [[ $# -lt 2 ]]; then
        log_error "Insufficient parameters for extraction"
        return 1
    fi
    
    # Enhanced path resolution with symlink handling
    if ! resolved_input="$(resolve_path "$1")"; then
        log_error "Cannot resolve input path: $1"
        return 1
    fi
    
    if ! resolved_output="$(resolve_path "$2" 2>/dev/null)"; then
        resolved_output="$2"
    fi
    
    # Create output directory if it doesn't exist for proper resolution
    if mkdir -p "$(dirname "$resolved_output")" 2>/dev/null; then
        if ! resolved_output="$(resolve_path "$resolved_output" 2>/dev/null)"; then
            resolved_output="$2"
        fi
    fi
    
    input_file="$resolved_input"
    output_dir="$resolved_output"
    
    log_debug "Resolved paths: Input=$input_file Output=$output_dir"
    
    # Comprehensive input validation
    if [[ ! -f $input_file ]]; then
        log_error "File not found: $input_file"
        return 1
    fi
    
    if [[ ! -r $input_file ]]; then
        log_error "File not readable: $input_file"
        return 1
    fi
    
    # Check for circular symlinks or invalid paths
    if [[ -L "$1" ]]; then
        log_info "Following symlink: $1 -> $input_file"
    fi
    
    # Output directory handling
    if [[ -e $output_dir ]]; then
        if [[ ! -d $output_dir ]]; then
            log_error "Output exists but is not a directory: $output_dir"
            return 1
        fi
        
        if [[ $FORCE != true ]]; then
            local dir_contents=""
            dir_contents="$(ls -A "$output_dir" 2>/dev/null)"
            if [[ -n $dir_contents ]]; then
                log_error "Directory not empty (use --force): $output_dir"
                return 1
            fi
        fi
    fi
    
    # Process archive
    if ! archive_type="$(detect_archive_type "$input_file")"; then
        return 1
    fi
    
    if ! validate_archive "$input_file" "$archive_type"; then
        return 1
    fi
    
    if ! extract_archive "$input_file" "$output_dir" "$archive_type"; then
        return 1
    fi
    
    if ! flatten_directories "$output_dir"; then
        log_warn "Flattening issues encountered"
    fi
    
    if ! show_results "$output_dir"; then
        log_warn "Failed to show results"
    fi
    
    return 0
}

# Argument parsing (enhanced with proper conditional logic)
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input) 
                if [[ $# -lt 2 ]]; then
                    log_error "Option $1 requires an argument"
                    return 1
                fi
                INPUT_FILE="$2"
                shift 2 
                ;;
            -o|--output) 
                if [[ $# -lt 2 ]]; then
                    log_error "Option $1 requires an argument"
                    return 1
                fi
                OUTPUT_DIR="$2"
                shift 2 
                ;;
            -f|--force) 
                FORCE=true
                shift 
                ;;
            -q|--quiet) 
                QUIET=true
                VERBOSE=false
                shift 
                ;;
            -v|--verbose) 
                VERBOSE=true
                QUIET=false
                shift 
                ;;
            -n|--no-flatten) 
                FLATTEN=false
                shift 
                ;;
            -t|--tree) 
                TREE_OUTPUT=true
                shift 
                ;;
            -h|--help) 
                show_help
                exit 0 
                ;;
            --) 
                shift
                break 
                ;;
            -*) 
                log_error "Unknown option: $1"
                return 1 
                ;;
            *) 
                if [[ -z $INPUT_FILE ]]; then
                    INPUT_FILE="$1"
                elif [[ -z $OUTPUT_DIR ]]; then
                    OUTPUT_DIR="$1"
                else
                    log_error "Too many arguments"
                    return 1
                fi
                shift 
                ;;
        esac
    done
    
    # Handle remaining positional args
    while [[ $# -gt 0 ]]; do
        if [[ -z $INPUT_FILE ]]; then
            INPUT_FILE="$1"
        elif [[ -z $OUTPUT_DIR ]]; then
            OUTPUT_DIR="$1"
        else
            log_error "Too many arguments"
            return 1
        fi
        shift
    done
    
    return 0
}

# Main function
main() {
    if ! parse_arguments "$@"; then
        exit 1
    fi
    
    if [[ -z $INPUT_FILE ]]; then
        log_error "No input file specified"
        exit 1
    fi
    
    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="."
    fi
    
    if ! check_dependencies; then
        exit 1
    fi
    
    if [[ $VERBOSE == true ]]; then
        log_info "Config: Input=${YELLOW}$INPUT_FILE${RESET} Output=${YELLOW}$OUTPUT_DIR${RESET} Force=$FORCE Flatten=$FLATTEN Tree=$TREE_OUTPUT"
    fi
    
    if ! extract_main "$INPUT_FILE" "$OUTPUT_DIR"; then
        exit 1
    fi
    
    return 0
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi