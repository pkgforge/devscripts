package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/fatih/color"
	"github.com/mholt/archives"
	"github.com/schollz/progressbar/v3"
	"github.com/urfave/cli/v3"
)

const (
	Version        = "2.0.1"
	MaxConcurrency = 4
	BufferSize     = 64 * 1024 // 64KB buffer for file operations
)

// Config holds the application configuration
type Config struct {
	Verbose     bool
	Quiet       bool
	Force       bool
	Flatten     bool
	TreeOutput  bool
	InputFile   string
	OutputDir   string
	MaxRetries  int
	Concurrency int
}

// Logger provides colorized logging functionality with thread safety
type Logger struct {
	config *Config
	mutex  sync.RWMutex
	red    func(a ...interface{}) string
	green  func(a ...interface{}) string
	yellow func(a ...interface{}) string
	blue   func(a ...interface{}) string
	cyan   func(a ...interface{}) string
}

// NewLogger creates a new logger instance
func NewLogger(config *Config) *Logger {
	return &Logger{
		config: config,
		red:    color.New(color.FgRed).SprintFunc(),
		green:  color.New(color.FgGreen).SprintFunc(),
		yellow: color.New(color.FgYellow).SprintFunc(),
		blue:   color.New(color.FgBlue).SprintFunc(),
		cyan:   color.New(color.FgCyan).SprintFunc(),
	}
}

func (l *Logger) logf(level, format string, color func(a ...interface{}) string, args ...interface{}) {
	l.mutex.RLock()
	defer l.mutex.RUnlock()
	if !l.config.Quiet {
		fmt.Fprintf(os.Stderr, color("["+level+"] ")+format+"\n", args...)
	}
}

func (l *Logger) Error(format string, args ...interface{}) {
	l.logf("ERROR", format, l.red, args...)
}

func (l *Logger) Warn(format string, args ...interface{}) {
	l.logf("WARN", format, l.yellow, args...)
}

func (l *Logger) Info(format string, args ...interface{}) {
	l.logf("INFO", format, l.green, args...)
}

func (l *Logger) Debug(format string, args ...interface{}) {
	if l.config.Verbose {
		l.logf("DEBUG", format, l.blue, args...)
	}
}

func (l *Logger) Success(format string, args ...interface{}) {
	l.logf("SUCCESS", format, l.green, args...)
}

// FileEntry represents a file in the archive
type FileEntry struct {
	Name     string    `json:"name"`
	Size     int64     `json:"size"`
	ModTime  time.Time `json:"mod_time"`
	IsDir    bool      `json:"is_dir"`
	LinkName string    `json:"link_name,omitempty"`
	Mode     string    `json:"mode"`
}

// ExtractStats holds extraction statistics
type ExtractStats struct {
	FilesExtracted     int           `json:"files_extracted"`
	DirsCreated        int           `json:"dirs_created"`
	BytesExtracted     int64         `json:"bytes_extracted"`
	DirsFlattened      int           `json:"dirs_flattened"`
	StartTime          time.Time     `json:"start_time"`
	EndTime            time.Time     `json:"end_time"`
	Duration           time.Duration `json:"duration"`
	ErrorsEncountered  int           `json:"errors_encountered"`
	FilesSkipped       int           `json:"files_skipped"`
}

// Extractor handles archive extraction operations
type Extractor struct {
	logger      *Logger
	config      *Config
	stats       *ExtractStats
	extractMux  sync.Mutex
	errorsMux   sync.Mutex
	errors      []error
	semaphore   chan struct{}
}

// NewExtractor creates a new extractor instance
func NewExtractor(config *Config) *Extractor {
	if config.MaxRetries == 0 {
		config.MaxRetries = 3
	}
	if config.Concurrency == 0 {
		config.Concurrency = min(MaxConcurrency, runtime.NumCPU())
	}
	
	return &Extractor{
		logger:    NewLogger(config),
		config:    config,
		stats:     &ExtractStats{StartTime: time.Now()},
		errors:    make([]error, 0),
		semaphore: make(chan struct{}, config.Concurrency),
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// Color helper methods for Extractor
func (e *Extractor) cyan(text string) string  { return e.logger.cyan(text) }
func (e *Extractor) yellow(text string) string { return e.logger.yellow(text) }
func (e *Extractor) blue(text string) string   { return e.logger.blue(text) }

// ValidateInputs performs comprehensive input validation with better error handling
func (e *Extractor) ValidateInputs() error {
	if e.config.InputFile == "" {
		return fmt.Errorf("input file is required")
	}

	// Resolve and validate input file
	inputPath, err := filepath.Abs(e.config.InputFile)
	if err != nil {
		return fmt.Errorf("failed to resolve input path %q: %w", e.config.InputFile, err)
	}
	e.config.InputFile = inputPath

	info, err := os.Stat(e.config.InputFile)
	if err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", e.config.InputFile)
		}
		if os.IsPermission(err) {
			return fmt.Errorf("permission denied accessing file: %s", e.config.InputFile)
		}
		return fmt.Errorf("cannot access file %s: %w", e.config.InputFile, err)
	}
	
	if info.IsDir() {
		return fmt.Errorf("input is a directory, expected file: %s", e.config.InputFile)
	}
	
	if info.Size() == 0 {
		return fmt.Errorf("input file is empty: %s", e.config.InputFile)
	}

	// Handle output directory with better validation
	if e.config.OutputDir == "" {
		e.config.OutputDir = "."
	}

	outputPath, err := filepath.Abs(e.config.OutputDir)
	if err != nil {
		return fmt.Errorf("failed to resolve output path %q: %w", e.config.OutputDir, err)
	}
	e.config.OutputDir = outputPath

	// Prevent extraction into same directory as archive
	inputDir := filepath.Dir(e.config.InputFile)
	if e.config.OutputDir == inputDir && !e.config.Force {
		return fmt.Errorf("output directory same as input directory (use --force to override)")
	}

	// Check output directory status
	if info, err := os.Stat(e.config.OutputDir); err == nil {
		if !info.IsDir() {
			return fmt.Errorf("output path exists but is not a directory: %s", e.config.OutputDir)
		}
		
		if !e.config.Force {
			if isEmpty, err := e.isDirEmpty(e.config.OutputDir); err != nil {
				return fmt.Errorf("failed to check output directory: %w", err)
			} else if !isEmpty {
				return fmt.Errorf("output directory not empty (use --force to override): %s", e.config.OutputDir)
			}
		}
	}

	e.logger.Debug("Input validation completed successfully")
	return nil
}

// isDirEmpty checks if a directory is empty with better error handling
func (e *Extractor) isDirEmpty(dir string) (bool, error) {
	f, err := os.Open(dir)
	if err != nil {
		return false, fmt.Errorf("failed to open directory %s: %w", dir, err)
	}
	defer f.Close()

	_, err = f.Readdir(1)
	return err == io.EOF, nil
}

// DetectAndValidateArchive detects archive format with retry logic
func (e *Extractor) DetectAndValidateArchive(ctx context.Context) (archives.Format, error) {
	var format archives.Format
	var err error

	for attempt := 1; attempt <= e.config.MaxRetries; attempt++ {
		file, openErr := os.Open(e.config.InputFile)
		if openErr != nil {
			return nil, fmt.Errorf("failed to open archive: %w", openErr)
		}

		format, _, err = archives.Identify(ctx, e.config.InputFile, file)
		file.Close()

		if err == nil {
			break
		}

		e.logger.Debug("Archive identification attempt %d/%d failed: %v", attempt, e.config.MaxRetries, err)
		if attempt < e.config.MaxRetries {
			time.Sleep(time.Duration(attempt) * 100 * time.Millisecond)
		}
	}

	if err != nil {
		return nil, fmt.Errorf("failed to identify archive format after %d attempts: %w", e.config.MaxRetries, err)
	}

	if _, ok := format.(archives.Extractor); !ok {
		return nil, fmt.Errorf("archive format %T does not support extraction", format)
	}

	e.logger.Debug("Archive format detected: %T", format)
	return format, nil
}

// ExtractArchive performs extraction with improved error handling and progress tracking
func (e *Extractor) ExtractArchive(ctx context.Context, format archives.Format) error {
	if err := os.MkdirAll(e.config.OutputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	file, err := os.Open(e.config.InputFile)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer file.Close()

	_, input, err := archives.Identify(ctx, e.config.InputFile, file)
	if err != nil {
		return fmt.Errorf("failed to re-identify archive: %w", err)
	}

	extractor := format.(archives.Extractor)

	// Count entries for progress tracking
	var progressBar *progressbar.ProgressBar
	if !e.config.Quiet {
		if totalEntries, countErr := e.countArchiveEntries(ctx, format); countErr == nil {
			progressBar = progressbar.NewOptions(totalEntries,
				progressbar.OptionSetDescription("Extracting"),
				progressbar.OptionSetPredictTime(true),
				progressbar.OptionShowCount(),
				progressbar.OptionSetTheme(progressbar.Theme{
					Saucer: "█", SaucerHead: "█", SaucerPadding: "░",
					BarStart: "[", BarEnd: "]",
				}),
			)
		}
	}

	e.logger.Info("Extracting %s: %s", e.cyan(filepath.Base(e.config.InputFile)), e.yellow(e.config.InputFile))

	// Extract with concurrent processing
	var wg sync.WaitGroup
	handler := func(ctx context.Context, f archives.FileInfo) error {
		if progressBar != nil {
			progressBar.Add(1)
		}

		wg.Add(1)
		e.semaphore <- struct{}{} // Acquire semaphore

		go func() {
			defer wg.Done()
			defer func() { <-e.semaphore }() // Release semaphore

			if err := e.extractFile(ctx, f); err != nil {
				e.errorsMux.Lock()
				e.errors = append(e.errors, fmt.Errorf("failed to extract %s: %w", f.NameInArchive, err))
				e.stats.ErrorsEncountered++
				e.errorsMux.Unlock()
				e.logger.Warn("Failed to extract %s: %v", f.NameInArchive, err)
			}
		}()

		return nil
	}

	err = extractor.Extract(ctx, input, handler)
	wg.Wait() // Wait for all extractions to complete

	if progressBar != nil {
		progressBar.Finish()
		fmt.Fprintln(os.Stderr)
	}

	if err != nil {
		return fmt.Errorf("extraction failed: %w", err)
	}

	if len(e.errors) > 0 {
		e.logger.Warn("Extraction completed with %d errors", len(e.errors))
	}

	return nil
}

// countArchiveEntries counts total entries with better error handling
func (e *Extractor) countArchiveEntries(ctx context.Context, format archives.Format) (int, error) {
	file, err := os.Open(e.config.InputFile)
	if err != nil {
		return 0, err
	}
	defer file.Close()

	_, input, err := archives.Identify(ctx, e.config.InputFile, file)
	if err != nil {
		return 0, err
	}

	extractor := format.(archives.Extractor)
	count := 0
	handler := func(ctx context.Context, f archives.FileInfo) error {
		count++
		return nil
	}

	err = extractor.Extract(ctx, input, handler)
	return count, err
}

// extractFile extracts a single file with enhanced security and error handling
func (e *Extractor) extractFile(ctx context.Context, f archives.FileInfo) error {
	targetPath := filepath.Join(e.config.OutputDir, f.NameInArchive)
	targetPath = filepath.Clean(targetPath)

	// Enhanced security: prevent directory traversal
	outputDir := filepath.Clean(e.config.OutputDir) + string(os.PathSeparator)
	if !strings.HasPrefix(targetPath+string(os.PathSeparator), outputDir) {
		e.stats.FilesSkipped++
		return fmt.Errorf("path traversal detected, skipping: %s", f.NameInArchive)
	}

	e.logger.Debug("Extracting: %s -> %s", f.NameInArchive, targetPath)

	if f.IsDir() {
		if err := os.MkdirAll(targetPath, 0755); err != nil {
			return fmt.Errorf("failed to create directory: %w", err)
		}
		e.extractMux.Lock()
		e.stats.DirsCreated++
		e.extractMux.Unlock()
		return nil
	}

	// Create parent directories
	if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
		return fmt.Errorf("failed to create parent directories: %w", err)
	}

	// Handle symlinks
	if f.Mode()&os.ModeSymlink != 0 {
		e.logger.Debug("Skipping symlink: %s", f.NameInArchive)
		e.stats.FilesSkipped++
		return nil
	}

	// Extract regular file with buffered I/O
	reader, err := f.Open()
	if err != nil {
		return fmt.Errorf("failed to open archive file: %w", err)
	}
	defer reader.Close()

	writer, err := os.OpenFile(targetPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, f.Mode()&0777)
	if err != nil {
		return fmt.Errorf("failed to create target file: %w", err)
	}
	defer writer.Close()

	// Use buffered copying for better performance
	written, err := io.CopyBuffer(writer, reader, make([]byte, BufferSize))
	if err != nil {
		os.Remove(targetPath) // Cleanup on failure
		return fmt.Errorf("failed to copy file data: %w", err)
	}

	// Set timestamps (permissions already set during file creation)
	if err := os.Chtimes(targetPath, time.Now(), f.ModTime()); err != nil {
		e.logger.Debug("Failed to set timestamps for %s: %v", targetPath, err)
	}

	e.extractMux.Lock()
	e.stats.FilesExtracted++
	e.stats.BytesExtracted += written
	e.extractMux.Unlock()

	return nil
}

// FlattenDirectories with improved logic and safety checks
func (e *Extractor) FlattenDirectories() error {
	if !e.config.Flatten {
		return nil
	}

	flattened := 0
	maxIterations := 10 // Prevent infinite loops

	for i := 0; i < maxIterations; i++ {
		entries, err := os.ReadDir(e.config.OutputDir)
		if err != nil {
			return fmt.Errorf("failed to read output directory: %w", err)
		}

		dirs := make([]os.DirEntry, 0)
		files := make([]os.DirEntry, 0)
		
		for _, entry := range entries {
			if entry.IsDir() {
				dirs = append(dirs, entry)
			} else {
				files = append(files, entry)
			}
		}

		// Only flatten if there's exactly one directory and no files at root level
		if len(dirs) != 1 || len(files) > 0 {
			break
		}

		dirPath := filepath.Join(e.config.OutputDir, dirs[0].Name())
		dirEntries, err := os.ReadDir(dirPath)
		if err != nil || len(dirEntries) == 0 {
			break
		}

		e.logger.Info("Flattening: %s", e.cyan(dirs[0].Name()))

		// Move contents with conflict resolution
		moveCount := 0
		for _, entry := range dirEntries {
			srcPath := filepath.Join(dirPath, entry.Name())
			dstPath := filepath.Join(e.config.OutputDir, entry.Name())

			if _, err := os.Stat(dstPath); err == nil {
				if !e.config.Force {
					e.logger.Warn("Destination exists, skipping: %s", entry.Name())
					continue
				}
				if err := os.RemoveAll(dstPath); err != nil {
					e.logger.Warn("Failed to remove existing: %s", entry.Name())
					continue
				}
			}

			if err := os.Rename(srcPath, dstPath); err != nil {
				e.logger.Warn("Failed to move %s: %v", entry.Name(), err)
				break
			}
			moveCount++
		}

		if moveCount == len(dirEntries) {
			if err := os.Remove(dirPath); err == nil {
				flattened++
			}
		} else {
			break
		}
	}

	if flattened > 0 {
		e.stats.DirsFlattened = flattened
		e.logger.Success("Flattened %d director%s", flattened, map[bool]string{true: "y", false: "ies"}[flattened == 1])
	}

	return nil
}

// ShowResults displays comprehensive extraction results
func (e *Extractor) ShowResults() error {
	e.stats.EndTime = time.Now()
	e.stats.Duration = e.stats.EndTime.Sub(e.stats.StartTime)

	e.logger.Success("Extraction completed in %v", e.stats.Duration.Round(time.Millisecond))
	e.logger.Success("Files: %d, Directories: %d, Size: %s",
		e.stats.FilesExtracted, e.stats.DirsCreated, formatBytes(e.stats.BytesExtracted))

	if e.stats.DirsFlattened > 0 {
		e.logger.Success("Flattened: %d directories", e.stats.DirsFlattened)
	}

	if e.stats.FilesSkipped > 0 {
		e.logger.Info("Skipped: %d files", e.stats.FilesSkipped)
	}

	if e.stats.ErrorsEncountered > 0 {
		e.logger.Warn("Errors encountered: %d", e.stats.ErrorsEncountered)
	}

	e.logger.Success("Output: %s", e.cyan(e.config.OutputDir))

	if e.config.TreeOutput {
		return e.showTree()
	}
	if e.config.Verbose {
		return e.showContents()
	}
	return nil
}

// showTree displays optimized tree view
func (e *Extractor) showTree() error {
	e.logger.Info("Directory structure:")
	
	var entries []string
	err := filepath.WalkDir(e.config.OutputDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || path == e.config.OutputDir {
			return err
		}
		if relPath, err := filepath.Rel(e.config.OutputDir, path); err == nil {
			entries = append(entries, relPath)
		}
		return nil
	})

	if err != nil {
		return err
	}

	sort.Strings(entries)
	displayed := 0
	const maxDisplay = 50

	for _, entry := range entries {
		if displayed >= maxDisplay {
			fmt.Printf("... and %d more items\n", len(entries)-maxDisplay)
			break
		}

		depth := strings.Count(entry, string(filepath.Separator))
		if depth > 4 { // Limit depth
			continue
		}

		name := filepath.Base(entry)
		indent := strings.Repeat("  ", depth)
		
		if info, err := os.Stat(filepath.Join(e.config.OutputDir, entry)); err == nil && info.IsDir() {
			name = e.blue(name + "/")
		}
		
		fmt.Printf("%s├── %s\n", indent, name)
		displayed++
	}
	return nil
}

// showContents displays detailed file listing
func (e *Extractor) showContents() error {
	e.logger.Info("Contents:")
	entries, err := os.ReadDir(e.config.OutputDir)
	if err != nil {
		return fmt.Errorf("failed to read output directory: %w", err)
	}

	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil {
			continue
		}

		name := entry.Name()
		if entry.IsDir() {
			name = e.blue(name + "/")
		}

		fmt.Printf("  %s  %8s  %s  %s\n",
			info.Mode().String(),
			formatBytes(info.Size()),
			info.ModTime().Format("2006-01-02 15:04"),
			name)
	}
	return nil
}

// formatBytes formats byte size in human-readable format
func formatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

// Extract performs the complete extraction process
func (e *Extractor) Extract(ctx context.Context) error {
	if err := e.ValidateInputs(); err != nil {
		return err
	}
	
	format, err := e.DetectAndValidateArchive(ctx)
	if err != nil {
		return err
	}
	
	// If flattening is enabled, extract to a temporary directory first
	var tempDir string
	var actualOutputDir string
	
	if e.config.Flatten {
		// Create temporary directory for extraction
		tempDir, err = os.MkdirTemp("", "extraxtor-*")
		if err != nil {
			return fmt.Errorf("failed to create temporary directory: %w", err)
		}
		defer os.RemoveAll(tempDir) // Clean up temp dir
		
		// Store the actual output directory and use temp dir for extraction
		actualOutputDir = e.config.OutputDir
		e.config.OutputDir = tempDir
		
		e.logger.Debug("Using temporary directory for flattening: %s", tempDir)
	}
	
	if err := e.ExtractArchive(ctx, format); err != nil {
		return err
	}
	
	// Perform flattening in the temporary directory
	if e.config.Flatten {
		if err := e.FlattenDirectories(); err != nil {
			e.logger.Warn("Directory flattening issues: %v", err)
		}
		
		// Restore original output directory
		e.config.OutputDir = actualOutputDir
		
		// Now move flattened contents to the actual output directory
		if err := e.moveExtractedContents(tempDir, actualOutputDir); err != nil {
			return fmt.Errorf("failed to move extracted contents: %w", err)
		}
	}
	
	return e.ShowResults()
}

// moveExtractedContents moves contents from temp directory to final output directory
func (e *Extractor) moveExtractedContents(srcDir, dstDir string) error {
	// Ensure destination directory exists
	if err := os.MkdirAll(dstDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}
	
	entries, err := os.ReadDir(srcDir)
	if err != nil {
		return fmt.Errorf("failed to read temporary directory: %w", err)
	}
	
	e.logger.Debug("Moving %d items from temp to output directory", len(entries))
	
	for _, entry := range entries {
		srcPath := filepath.Join(srcDir, entry.Name())
		dstPath := filepath.Join(dstDir, entry.Name())
		
		// Handle existing files/directories in destination
		if _, err := os.Stat(dstPath); err == nil {
			if !e.config.Force {
				e.logger.Warn("Destination exists, skipping: %s", entry.Name())
				continue
			}
			// Force enabled: remove existing
			if err := os.RemoveAll(dstPath); err != nil {
				e.logger.Warn("Failed to remove existing %s: %v", entry.Name(), err)
				continue
			}
			e.logger.Debug("Removed existing: %s", entry.Name())
		}
		
		// Move the file/directory
		if err := os.Rename(srcPath, dstPath); err != nil {
			// If rename fails (cross-device), try copy + remove
			if err := e.copyAndRemove(srcPath, dstPath); err != nil {
				e.logger.Warn("Failed to move %s: %v", entry.Name(), err)
				continue
			}
		}
		
		e.logger.Debug("Moved: %s -> %s", srcPath, dstPath)
	}
	
	return nil
}

// copyAndRemove copies a file/directory and removes the source (for cross-device moves)
func (e *Extractor) copyAndRemove(src, dst string) error {
	srcInfo, err := os.Stat(src)
	if err != nil {
		return err
	}
	
	if srcInfo.IsDir() {
		// Copy directory recursively
		err := filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			
			relPath, err := filepath.Rel(src, path)
			if err != nil {
				return err
			}
			
			dstPath := filepath.Join(dst, relPath)
			
			if d.IsDir() {
				return os.MkdirAll(dstPath, d.Type())
			} else {
				return e.copyFile(path, dstPath)
			}
		})
		
		if err != nil {
			return err
		}
		
		return os.RemoveAll(src)
	} else {
		// Copy single file
		if err := e.copyFile(src, dst); err != nil {
			return err
		}
		return os.Remove(src)
	}
}

// copyFile copies a single file
func (e *Extractor) copyFile(src, dst string) error {
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()
	
	// Ensure destination directory exists
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	
	dstFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer dstFile.Close()
	
	_, err = io.CopyBuffer(dstFile, srcFile, make([]byte, BufferSize))
	if err != nil {
		return err
	}
	
	// Copy file permissions and timestamps
	srcInfo, err := srcFile.Stat()
	if err != nil {
		return err
	}
	
	if err := dstFile.Chmod(srcInfo.Mode()); err != nil {
		return err
	}
	
	return os.Chtimes(dst, time.Now(), srcInfo.ModTime())
}

func main() {
	app := &cli.Command{
		Name:    "extraxtor",
		Usage:   "Archive Extractor with Intelligent Directory Flattening",
		Version: Version,
		Authors: []any{"Rewritten in Go"},
		Flags: []cli.Flag{
			&cli.StringFlag{Name: "input", Aliases: []string{"i"}, Usage: "Input archive file"},
			&cli.StringFlag{Name: "output", Aliases: []string{"o"}, Usage: "Output directory (default: current directory)"},
			&cli.BoolFlag{Name: "force", Aliases: []string{"f"}, Usage: "Force extraction, overwrite existing files"},
			&cli.BoolFlag{Name: "quiet", Aliases: []string{"q"}, Usage: "Suppress all output except errors"},
			&cli.BoolFlag{Name: "debug", Aliases: []string{"d"}, Usage: "Enable debug output"}, // Changed from verbose to debug
			&cli.BoolFlag{Name: "no-flatten", Aliases: []string{"n"}, Usage: "Don't flatten nested single directories"},
			&cli.BoolFlag{Name: "tree", Aliases: []string{"t"}, Usage: "Show tree output after extraction"},
		},
		Action: func(ctx context.Context, c *cli.Command) error {
			config := &Config{
				Verbose:     c.Bool("debug"), // Use debug instead of verbose
				Quiet:       c.Bool("quiet"),
				Force:       c.Bool("force"),
				Flatten:     !c.Bool("no-flatten"),
				TreeOutput:  c.Bool("tree"),
				InputFile:   c.String("input"),
				OutputDir:   c.String("output"),
				MaxRetries:  3,
				Concurrency: min(MaxConcurrency, runtime.NumCPU()),
			}

			args := c.Args()
			if args.Len() > 0 && config.InputFile == "" {
				config.InputFile = args.Get(0)
			}
			if args.Len() > 1 && config.OutputDir == "" {
				config.OutputDir = args.Get(1)
			}

			if config.InputFile == "" {
				return fmt.Errorf("input file is required")
			}

			if config.Quiet && config.Verbose {
				config.Verbose = false
			}

			return NewExtractor(config).Extract(ctx)
		},
		Commands: []*cli.Command{{
			Name: "inspect", Aliases: []string{"ls", "list"}, Usage: "Inspect archive contents without extraction",
			Flags: []cli.Flag{
				&cli.BoolFlag{Name: "json", Usage: "Output in JSON format"},
				&cli.BoolFlag{Name: "tree", Usage: "Show tree format"},
				&cli.BoolFlag{Name: "debug", Aliases: []string{"d"}, Usage: "Show detailed information"},
			},
			Action: func(ctx context.Context, c *cli.Command) error {
				if archivePath := c.Args().First(); archivePath != "" {
					return inspectArchive(ctx, archivePath, c.Bool("json"), c.Bool("tree"), c.Bool("debug"))
				}
				return fmt.Errorf("archive path is required")
			},
		}},
	}

	if err := app.Run(context.Background(), os.Args); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// inspectArchive inspects archive contents with improved output
func inspectArchive(ctx context.Context, archivePath string, jsonOutput, treeOutput, verbose bool) error {
	file, err := os.Open(archivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer file.Close()

	format, input, err := archives.Identify(ctx, archivePath, file)
	if err != nil {
		return fmt.Errorf("failed to identify archive format: %w", err)
	}

	extractor, ok := format.(archives.Extractor)
	if !ok {
		return fmt.Errorf("unsupported archive format for inspection")
	}

	var entries []FileEntry
	var totalSize int64
	var fileCount, dirCount int

	handler := func(ctx context.Context, f archives.FileInfo) error {
		linkName := ""
		if f.Mode()&os.ModeSymlink != 0 {
			linkName = "<symlink>"
		}

		entries = append(entries, FileEntry{
			Name:     f.NameInArchive,
			Size:     f.Size(),
			ModTime:  f.ModTime(),
			IsDir:    f.IsDir(),
			LinkName: linkName,
			Mode:     f.Mode().String(),
		})

		if f.IsDir() {
			dirCount++
		} else {
			fileCount++
			totalSize += f.Size()
		}
		return nil
	}

	if err := extractor.Extract(ctx, input, handler); err != nil {
		return fmt.Errorf("failed to inspect archive: %w", err)
	}

	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Name < entries[j].Name
	})

	if jsonOutput {
		return json.NewEncoder(os.Stdout).Encode(map[string]interface{}{
			"entries":     entries,
			"file_count":  fileCount,
			"dir_count":   dirCount,
			"total_size":  totalSize,
			"total_items": len(entries),
		})
	}

	if treeOutput {
		for _, entry := range entries {
			prefix := map[bool]string{true: "📁 ", false: "📄 "}[entry.IsDir]
			fmt.Printf("%s%s\n", prefix, entry.Name)
		}
		return nil
	}

	if verbose {
		fmt.Printf("Archive: %s (%d files, %d directories, %s total)\n\n",
			filepath.Base(archivePath), fileCount, dirCount, formatBytes(totalSize))
	}

	for _, entry := range entries {
		if verbose {
			fmt.Printf("%s %8s %s %s\n",
				entry.Mode, formatBytes(entry.Size),
				entry.ModTime.Format("2006-01-02 15:04"), entry.Name)
		} else {
			fmt.Println(entry.Name)
		}
	}

	if verbose {
		fmt.Printf("\nSummary: %d files, %d directories, %s total\n",
			fileCount, dirCount, formatBytes(totalSize))
	}

	return nil
}