package main

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/fatih/color"
	"github.com/mholt/archives"
	"github.com/schollz/progressbar/v3"
	"github.com/urfave/cli/v3"
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
}

// Logger provides colorized logging functionality
type Logger struct {
	config *Config
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

func (l *Logger) Error(format string, args ...interface{}) {
	if !l.config.Quiet {
		fmt.Fprintf(os.Stderr, l.red("[ERROR] ")+format+"\n", args...)
	}
}

func (l *Logger) Warn(format string, args ...interface{}) {
	if !l.config.Quiet {
		fmt.Fprintf(os.Stderr, l.yellow("[WARN] ")+format+"\n", args...)
	}
}

func (l *Logger) Info(format string, args ...interface{}) {
	if !l.config.Quiet {
		fmt.Fprintf(os.Stderr, l.green("[INFO] ")+format+"\n", args...)
	}
}

func (l *Logger) Debug(format string, args ...interface{}) {
	if l.config.Verbose {
		fmt.Fprintf(os.Stderr, l.blue("[DEBUG] ")+format+"\n", args...)
	}
}

func (l *Logger) Success(format string, args ...interface{}) {
	if !l.config.Quiet {
		fmt.Fprintf(os.Stderr, l.green("[SUCCESS] ")+format+"\n", args...)
	}
}

// FileEntry represents a file in the archive
type FileEntry struct {
	Name     string
	Size     int64
	ModTime  time.Time
	IsDir    bool
	LinkName string
}

// ExtractStats holds extraction statistics
type ExtractStats struct {
	FilesExtracted     int
	DirsCreated        int
	BytesExtracted     int64
	DirsFlattened      int
	StartTime          time.Time
	EndTime            time.Time
}

// Extractor handles archive extraction operations
type Extractor struct {
	logger *Logger
	config *Config
	stats  *ExtractStats
}

// NewExtractor creates a new extractor instance
func NewExtractor(config *Config) *Extractor {
	return &Extractor{
		logger: NewLogger(config),
		config: config,
		stats:  &ExtractStats{StartTime: time.Now()},
	}
}

// Color helper methods for Extractor
func (e *Extractor) cyan(text string) string {
	return e.logger.cyan(text)
}

func (e *Extractor) yellow(text string) string {
	return e.logger.yellow(text)
}

func (e *Extractor) blue(text string) string {
	return e.logger.blue(text)
}

// ValidateInputs performs comprehensive input validation
func (e *Extractor) ValidateInputs() error {
	// Check input file
	if e.config.InputFile == "" {
		return fmt.Errorf("input file is required")
	}

	// Resolve input file path
	inputPath, err := filepath.Abs(e.config.InputFile)
	if err != nil {
		return fmt.Errorf("failed to resolve input path: %w", err)
	}
	e.config.InputFile = inputPath

	// Check if input file exists and is readable
	if info, err := os.Stat(e.config.InputFile); err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", e.config.InputFile)
		}
		return fmt.Errorf("cannot access file: %s (%w)", e.config.InputFile, err)
	} else if info.IsDir() {
		return fmt.Errorf("input is a directory, not a file: %s", e.config.InputFile)
	}

	// Handle output directory
	if e.config.OutputDir == "" {
		e.config.OutputDir = "."
	}

	outputPath, err := filepath.Abs(e.config.OutputDir)
	if err != nil {
		return fmt.Errorf("failed to resolve output path: %w", err)
	}
	e.config.OutputDir = outputPath

	// Check output directory
	if info, err := os.Stat(e.config.OutputDir); err == nil {
		if !info.IsDir() {
			return fmt.Errorf("output exists but is not a directory: %s", e.config.OutputDir)
		}
		// Check if directory is empty (unless force is used)
		if !e.config.Force {
			isEmpty, err := e.isDirEmpty(e.config.OutputDir)
			if err != nil {
				return fmt.Errorf("failed to check output directory: %w", err)
			}
			if !isEmpty {
				return fmt.Errorf("output directory is not empty (use --force to override): %s", e.config.OutputDir)
			}
		}
	}

	return nil
}

// isDirEmpty checks if a directory is empty
func (e *Extractor) isDirEmpty(dir string) (bool, error) {
	f, err := os.Open(dir)
	if err != nil {
		return false, err
	}
	defer f.Close()

	_, err = f.Readdir(1)
	if err == io.EOF {
		return true, nil
	}
	return false, err
}

// DetectAndValidateArchive detects archive format and validates it
func (e *Extractor) DetectAndValidateArchive(ctx context.Context) (archives.Format, error) {
	file, err := os.Open(e.config.InputFile)
	if err != nil {
		return nil, fmt.Errorf("failed to open archive: %w", err)
	}
	defer file.Close()

	format, _, err := archives.Identify(ctx, e.config.InputFile, file)
	if err != nil {
		return nil, fmt.Errorf("failed to identify archive format: %w", err)
	}

	// Check if format supports extraction
	if _, ok := format.(archives.Extractor); !ok {
		return nil, fmt.Errorf("unsupported archive format for extraction")
	}

	e.logger.Debug("Detected archive format: %T", format)
	return format, nil
}

// ExtractArchive performs the main extraction operation
func (e *Extractor) ExtractArchive(ctx context.Context, format archives.Format) error {
	file, err := os.Open(e.config.InputFile)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer file.Close()

	// Re-identify to get the input stream
	_, input, err := archives.Identify(ctx, e.config.InputFile, file)
	if err != nil {
		return fmt.Errorf("failed to re-identify archive: %w", err)
	}

	extractor := format.(archives.Extractor)

	// Create output directory
	if err := os.MkdirAll(e.config.OutputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	// Get total entries for progress bar (if not quiet)
	var totalEntries int
	var progressBar *progressbar.ProgressBar
	if !e.config.Quiet {
		totalEntries, err = e.countArchiveEntries(ctx, format)
		if err != nil {
			e.logger.Warn("Failed to count archive entries: %v", err)
		} else {
			progressBar = progressbar.NewOptions(totalEntries,
				progressbar.OptionSetDescription("Extracting"),
				progressbar.OptionSetPredictTime(true),
				progressbar.OptionShowCount(),
				progressbar.OptionSetTheme(progressbar.Theme{
					Saucer:        "=",
					SaucerHead:    ">",
					SaucerPadding: " ",
					BarStart:      "[",
					BarEnd:        "]",
				}),
			)
		}
	}

	// Extract files
	handler := func(ctx context.Context, f archives.FileInfo) error {
		if progressBar != nil {
			progressBar.Add(1)
		}
		return e.extractFile(ctx, f)
	}

	e.logger.Info("Extracting %s: %s",
		e.cyan(filepath.Base(e.config.InputFile)),
		e.yellow(e.config.InputFile))

	err = extractor.Extract(ctx, input, handler)
	if err != nil {
		return fmt.Errorf("extraction failed: %w", err)
	}

	if progressBar != nil {
		progressBar.Finish()
		fmt.Fprintln(os.Stderr) // Add newline after progress bar
	}

	return nil
}

// countArchiveEntries counts the total number of entries in the archive
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

// extractFile extracts a single file from the archive
func (e *Extractor) extractFile(ctx context.Context, f archives.FileInfo) error {
	targetPath := filepath.Join(e.config.OutputDir, f.NameInArchive)

	// Clean the path to prevent directory traversal
	targetPath = filepath.Clean(targetPath)
	if !strings.HasPrefix(targetPath, filepath.Clean(e.config.OutputDir)+string(os.PathSeparator)) &&
		targetPath != filepath.Clean(e.config.OutputDir) {
		e.logger.Warn("Skipping file outside target directory: %s", f.NameInArchive)
		return nil
	}

	e.logger.Debug("Extracting: %s -> %s", f.NameInArchive, targetPath)

	if f.IsDir() {
		if err := os.MkdirAll(targetPath, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", targetPath, err)
		}
		e.stats.DirsCreated++
		return nil
	}

	// Create parent directories
	if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
		return fmt.Errorf("failed to create parent directories for %s: %w", targetPath, err)
	}

	// Handle symlinks - Check if this is a symbolic link
	// Note: archives.FileInfo doesn't directly provide link target info
	// We'll check the file mode to see if it's a symlink
	if f.Mode()&os.ModeSymlink != 0 {
		e.logger.Debug("Detected symlink: %s (skipping - symlink target not available)", f.NameInArchive)
		// Most archive formats don't provide easy access to symlink targets
		// This would need format-specific handling
		return nil
	}

	// Extract regular file
	reader, err := f.Open()
	if err != nil {
		return fmt.Errorf("failed to open file in archive: %w", err)
	}
	defer reader.Close()

	writer, err := os.Create(targetPath)
	if err != nil {
		return fmt.Errorf("failed to create file %s: %w", targetPath, err)
	}
	defer writer.Close()

	written, err := io.Copy(writer, reader)
	if err != nil {
		return fmt.Errorf("failed to write file %s: %w", targetPath, err)
	}

	// Set file permissions and timestamps
	if err := os.Chmod(targetPath, f.Mode()); err != nil {
		e.logger.Debug("Failed to set permissions for %s: %v", targetPath, err)
	}

	if err := os.Chtimes(targetPath, time.Now(), f.ModTime()); err != nil {
		e.logger.Debug("Failed to set timestamps for %s: %v", targetPath, err)
	}

	e.stats.FilesExtracted++
	e.stats.BytesExtracted += written

	return nil
}

// FlattenDirectories implements intelligent directory flattening
func (e *Extractor) FlattenDirectories() error {
	if !e.config.Flatten {
		e.logger.Debug("Directory flattening disabled")
		return nil
	}

	flattened := 0
	for {
		entries, err := os.ReadDir(e.config.OutputDir)
		if err != nil {
			return fmt.Errorf("failed to read output directory: %w", err)
		}

		// Filter out only directories
		var dirs []os.DirEntry
		for _, entry := range entries {
			if entry.IsDir() {
				dirs = append(dirs, entry)
			}
		}

		// Check if there's exactly one directory that can be flattened
		// Changed logic: only require one directory, not one total entry
		if len(dirs) == 1 {
			dirPath := filepath.Join(e.config.OutputDir, dirs[0].Name())

			// Check if directory has contents
			dirEntries, err := os.ReadDir(dirPath)
			if err != nil {
				e.logger.Warn("Failed to read directory for flattening: %s", dirPath)
				break
			}

			if len(dirEntries) == 0 {
				// Remove empty directory
				if err := os.Remove(dirPath); err != nil {
					e.logger.Warn("Failed to remove empty directory: %s", dirPath)
				}
				break
			}

			e.logger.Info("Flattening: %s", e.cyan(dirs[0].Name()))

			// Move all contents up one level
			for _, entry := range dirEntries {
				srcPath := filepath.Join(dirPath, entry.Name())
				dstPath := filepath.Join(e.config.OutputDir, entry.Name())

				// Check if destination already exists
				if _, err := os.Stat(dstPath); err == nil {
					if !e.config.Force {
						e.logger.Warn("Destination already exists, skipping: %s", entry.Name())
						continue
					}
					// Remove existing file/directory if force is enabled
					if err := os.RemoveAll(dstPath); err != nil {
						e.logger.Warn("Failed to remove existing destination %s: %v", entry.Name(), err)
						continue
					}
				}

				if err := os.Rename(srcPath, dstPath); err != nil {
					e.logger.Warn("Failed to move %s during flattening: %v", entry.Name(), err)
					return nil // Stop flattening on error
				}
			}

			// Remove the now-empty directory
			if err := os.Remove(dirPath); err != nil {
				e.logger.Warn("Failed to remove flattened directory: %s", dirPath)
			} else {
				flattened++
			}
		} else {
			break
		}
	}

	if flattened > 0 {
		e.stats.DirsFlattened = flattened
		dirWord := "directory"
		if flattened > 1 {
			dirWord = "directories"
		}
		e.logger.Success("Flattened %d %s", flattened, dirWord)
	}

	return nil
}

// ShowResults displays extraction results and statistics
func (e *Extractor) ShowResults() error {
	e.stats.EndTime = time.Now()
	duration := e.stats.EndTime.Sub(e.stats.StartTime)

	e.logger.Success("Extraction completed in %v", duration.Round(time.Millisecond))
	e.logger.Success("Files: %d, Directories: %d, Size: %s",
		e.stats.FilesExtracted,
		e.stats.DirsCreated,
		formatBytes(e.stats.BytesExtracted))

	if e.stats.DirsFlattened > 0 {
		e.logger.Success("Flattened: %d directories", e.stats.DirsFlattened)
	}

	e.logger.Success("Output: %s", e.cyan(e.config.OutputDir))

	// Show tree output if requested
	if e.config.TreeOutput {
		return e.showTree()
	}

	// Show verbose listing
	if e.config.Verbose {
		return e.showContents()
	}

	return nil
}

// showTree displays a tree view of extracted contents
func (e *Extractor) showTree() error {
	e.logger.Info("Directory structure:")

	// Collect all entries first
	var entries []string
	err := filepath.WalkDir(e.config.OutputDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		// Calculate relative path
		relPath, err := filepath.Rel(e.config.OutputDir, path)
		if err != nil {
			return err
		}

		if relPath == "." {
			return nil
		}

		entries = append(entries, relPath)
		return nil
	})

	if err != nil {
		return err
	}

	// Sort entries to ensure consistent output
	sort.Strings(entries)

	// Display tree
	for i, entry := range entries {
		if len(entries) > 20 && i >= 20 { // Limit output for very large directories
			fmt.Printf("... and %d more items\n", len(entries)-20)
			break
		}

		depth := strings.Count(entry, string(filepath.Separator))
		if depth > 3 { // Limit tree depth
			continue
		}

		// Create proper tree indentation
		parts := strings.Split(entry, string(filepath.Separator))
		name := parts[len(parts)-1]
		
		// Build indentation
		indent := strings.Repeat("  ", depth)
		
		// Check if it's a directory by trying to stat it
		fullPath := filepath.Join(e.config.OutputDir, entry)
		if info, err := os.Stat(fullPath); err == nil && info.IsDir() {
			name = e.blue(name + "/")
		}

		fmt.Printf("%s├── %s\n", indent, name)
	}

	return nil
}

// showContents displays detailed contents listing
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
	// Validate inputs
	if err := e.ValidateInputs(); err != nil {
		return err
	}

	// Detect and validate archive format
	format, err := e.DetectAndValidateArchive(ctx)
	if err != nil {
		return err
	}

	// Extract archive
	if err := e.ExtractArchive(ctx, format); err != nil {
		return err
	}

	// Flatten directories if requested
	if err := e.FlattenDirectories(); err != nil {
		e.logger.Warn("Directory flattening encountered issues: %v", err)
	}

	// Show results
	return e.ShowResults()
}

func main() {
	app := &cli.Command{
		Name:    "extraxtor",
		Usage:   "Archive Extractor with Intelligent Directory Flattening",
		Version: "2.0.0",
		Authors: []any{"Rewritten in Go"}, // Fixed: changed from []string to []any
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:    "input",
				Aliases: []string{"i"},
				Usage:   "Input archive file",
			},
			&cli.StringFlag{
				Name:    "output",
				Aliases: []string{"o"},
				Usage:   "Output directory (default: current directory)",
			},
			&cli.BoolFlag{
				Name:    "force",
				Aliases: []string{"f"},
				Usage:   "Force extraction, overwrite existing files",
			},
			&cli.BoolFlag{
				Name:    "quiet",
				Aliases: []string{"q"},
				Usage:   "Suppress all output except errors",
			},
			&cli.BoolFlag{
				Name:    "verbose",
				Aliases: []string{"v"},
				Usage:   "Enable verbose output",
			},
			&cli.BoolFlag{
				Name:    "no-flatten",
				Aliases: []string{"n"},
				Usage:   "Don't flatten nested single directories",
				Value:   false,
			},
			&cli.BoolFlag{
				Name:    "tree",
				Aliases: []string{"t"},
				Usage:   "Show tree output after extraction",
			},
		},
		Action: func(ctx context.Context, c *cli.Command) error {
			config := &Config{
				Verbose:    c.Bool("verbose"),
				Quiet:      c.Bool("quiet"),
				Force:      c.Bool("force"),
				Flatten:    !c.Bool("no-flatten"),
				TreeOutput: c.Bool("tree"),
				InputFile:  c.String("input"),
				OutputDir:  c.String("output"),
			}

			// Handle positional arguments
			args := c.Args()
			if args.Len() > 0 && config.InputFile == "" {
				config.InputFile = args.Get(0)
			}
			if args.Len() > 1 && config.OutputDir == "" {
				config.OutputDir = args.Get(1)
			}

			// Validate required arguments
			if config.InputFile == "" {
				return fmt.Errorf("input file is required")
			}

			// Handle conflicting flags
			if config.Quiet && config.Verbose {
				config.Verbose = false
			}

			extractor := NewExtractor(config)
			return extractor.Extract(ctx)
		},
		Commands: []*cli.Command{
			{
				Name:    "inspect",
				Aliases: []string{"ls", "list"},
				Usage:   "Inspect archive contents without extraction",
				Flags: []cli.Flag{
					&cli.BoolFlag{
						Name:  "json",
						Usage: "Output in JSON format",
					},
					&cli.BoolFlag{
						Name:  "tree",
						Usage: "Show tree format",
					},
					&cli.BoolFlag{
						Name:    "verbose",
						Aliases: []string{"v"},
						Usage:   "Show detailed information",
					},
				},
				Action: func(ctx context.Context, c *cli.Command) error {
					archivePath := c.Args().First()
					if archivePath == "" {
						return fmt.Errorf("archive path is required")
					}
					return inspectArchive(ctx, archivePath, c.Bool("json"), c.Bool("tree"), c.Bool("verbose"))
				},
			},
		},
	}

	if err := app.Run(context.Background(), os.Args); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// inspectArchive inspects archive contents without extraction
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
		// Check if this is a symlink based on file mode
		linkName := ""
		if f.Mode()&os.ModeSymlink != 0 {
			// This is a symlink, but we can't easily get the target from archives.FileInfo
			// Different archive formats handle this differently
			linkName = "<symlink>" // Placeholder to indicate it's a symlink
		}

		entry := FileEntry{
			Name:     f.NameInArchive,
			Size:     f.Size(),
			ModTime:  f.ModTime(),
			IsDir:    f.IsDir(),
			LinkName: linkName,
		}
		entries = append(entries, entry)

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

	// Sort entries
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Name < entries[j].Name
	})

	// Output results
	if jsonOutput {
		return outputJSON(entries)
	}

	if treeOutput {
		return outputTree(entries)
	}

	return outputList(entries, verbose, fileCount, dirCount, totalSize)
}

// Helper functions for different output formats
func outputJSON(entries []FileEntry) error {
	// JSON output implementation
	fmt.Println("JSON output not implemented in this example")
	return nil
}

func outputTree(entries []FileEntry) error {
	// Tree output implementation
	for _, entry := range entries {
		prefix := ""
		if entry.IsDir {
			prefix = "📁 "
		} else {
			prefix = "📄 "
		}
		fmt.Printf("%s%s\n", prefix, entry.Name)
	}
	return nil
}

func outputList(entries []FileEntry, verbose bool, fileCount, dirCount int, totalSize int64) error {
	if verbose {
		fmt.Printf("Archive contains %d files and %d directories (%s total)\n\n",
			fileCount, dirCount, formatBytes(totalSize))
	}

	for _, entry := range entries {
		if verbose {
			mode := "-rw-r--r--"
			if entry.IsDir {
				mode = "drwxr-xr-x"
			}
			fmt.Printf("%s %8s %s %s\n",
				mode,
				formatBytes(entry.Size),
				entry.ModTime.Format("2006-01-02 15:04"),
				entry.Name)
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