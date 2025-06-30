### ℹ️ About
Archive Extractor with Intelligent Directory Flattening.<br>

### 🧰 Usage
```mathematica
❯ extraxtor --help

NAME:
   extraxtor - Archive Extractor with Intelligent Directory Flattening

USAGE:
   extraxtor [global options] [command [command options]]

VERSION:
   0.0.1

COMMANDS:
   inspect, ls, list  Inspect archive contents without extraction
   help, h            Shows a list of commands or help for one command

GLOBAL OPTIONS:
   --input string, -i string   Input archive file
   --output string, -o string  Output directory (default: current directory)
   --force, -f                 Force extraction, overwrite existing files (default: false)
   --quiet, -q                 Suppress all output except errors (default: false)
   --debug, -d                 Enable debug output (default: false)
   --no-flatten, -n            Don't flatten nested single directories (default: false)
   --tree, -t                  Show tree output after extraction (default: false)
   --help, -h                  show help
   --version, -v               print the version
```

### 🛠️ Building
```bash
curl -qfsSL 'https://github.com/pkgforge/devscripts/raw/refs/heads/main/Linux/extraxtor/main.go' -o "./main.go"
go mod init "github.com/pkgforge/devscripts/extraxtor"
go mod tidy -v

export CGO_ENABLED="0"
export GOARCH="amd64"
export GOOS="linux"

go build -a -v -x -trimpath \
         -buildvcs="false" \
         -ldflags="-s -w -buildid= -extldflags '-s -w -Wl,--build-id=none'" \
         -o "./extraxtor"

"./extraxtor" --help
```