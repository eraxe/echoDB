# SDBTT: Simple Database Transfer Tool

A retrowave-themed interface for MySQL database management, import, and transfer operations.

## Features

- Modern retrowave UI with interactive terminal dialogs
- Import SQL files to MySQL databases with automatic charset fixes
- Transfer and replace databases with a single operation
- Secure password management
- MySQL user and privilege management
- Database backup and restore with progress tracking
- Database integrity checking and optimization

## Installation

### Local Installation

Clone the repository and run the tool directly:

```bash
git clone https://github.com/eraxe/sdbtt.git
cd sdbtt
./bin/sdbtt
```

### System Installation

Install the tool system-wide:

```bash
sudo ./install.sh
```

Once installed, you can run the tool by typing `sdbtt` in your terminal.

## Usage

SDBTT provides both an interactive UI mode and a command-line interface:

### Interactive Mode

Simply run the command without arguments:

```bash
sdbtt
```

### Command Line Mode

```bash
# Import SQL files with prefix
sdbtt --user=root --prefix=mydb_ import

# Backup databases
sdbtt --user=admin backup

# List databases
sdbtt --user=root list
```

## Requirements

- MySQL/MariaDB server
- dialog (for the interactive UI)
- bash 4.0+
- Standard Unix utilities (sed, awk, etc.)

## Configuration

SDBTT configuration is stored in `~/.sdbtt/config.conf` and can be modified directly or through the interactive interface.

## License

MIT License. See LICENSE file for details.

## Credits

Created by eraxe