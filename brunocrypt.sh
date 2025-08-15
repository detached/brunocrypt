#!/bin/bash

# brunocrypt.sh - Encrypt and decrypt .env files in a directory structure
# Usage: ./brunocrypt.sh [--encrypt|--decrypt|--clean] [-f] [--recipient <email>] <directory>

set -e

# Default values
MODE=""
DIRECTORY=""
FORCE=false
RECIPIENT=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print usage information
usage() {
    echo "Usage: $0 [--encrypt|--decrypt|--clean] [-f] [--recipient <email>] <directory>"
    echo ""
    echo "Modes:"
    echo "  --encrypt, -e    Encrypt all .env files in the directory tree"
    echo "  --decrypt, -d    Decrypt all .env.gpg files in the directory tree"
    echo "  --clean, -c      Remove all .env files in the directory tree"
    echo ""
    echo "Options:"
    echo "  -f                    Force operation without confirmation (only for --clean)"
    echo "  --recipient <email>   GPG recipient email for encryption (required for --encrypt)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --encrypt ~/path/to/repository/ --recipient your@email.com"
    echo "  $0 --decrypt ~/path/to/repository/"
    echo "  $0 --clean -f ~/path/to/repository/"
}

# Log messages with colors
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if gpg is available
check_gpg() {
    if ! command -v gpg >/dev/null 2>&1; then
        log_error "GPG is not installed or not in PATH"
        exit 1
    fi
}

# Add *.gpg to .gitignore if not already present
update_gitignore() {
    local dir="$1"
    local gitignore_file="$dir/.gitignore"

    if [ -d "$dir/.git" ]; then
        if [ ! -f "$gitignore_file" ]; then
            echo "*.gpg" > "$gitignore_file"
            log_info "Created .gitignore with *.gpg entry"
        elif ! grep -q "^\*\.gpg$" "$gitignore_file"; then
            echo "*.gpg" >> "$gitignore_file"
            log_info "Added *.gpg to existing .gitignore"
        fi
    fi
}

# Encrypt all .env files in the directory tree
encrypt_env_files() {
    local dir="$1"

    check_gpg
    log_info "Encrypting .env files in: $dir"

    # Find all .env files
    local env_files
    env_files=$(find "$dir" -name ".env" -type f 2>/dev/null)

    if [ -z "$env_files" ]; then
        log_warning "No .env files found in $dir"
        return 0
    fi

    local count=0
    while IFS= read -r env_file; do
        if [ -n "$env_file" ]; then
            local gpg_file="${env_file}.gpg"
            log_info "Encrypting: $env_file -> $gpg_file"

            if gpg --recipient "$RECIPIENT" --encrypt --output "$gpg_file" "$env_file"; then
                log_success "Encrypted: $gpg_file"
                count=$((count + 1))
            else
                log_error "Failed to encrypt: $env_file"
            fi
        fi
    done <<< "$env_files"

    if [ $count -gt 0 ]; then
        update_gitignore "$dir"
        log_success "Encrypted $count .env file(s)"
    fi
}

# Decrypt all .env.gpg files in the directory tree
decrypt_env_files() {
    local dir="$1"

    check_gpg
    log_info "Decrypting .env.gpg files in: $dir"

    # Find all .env.gpg files
    local gpg_files
    gpg_files=$(find "$dir" -name ".env.gpg" -type f 2>/dev/null)

    if [ -z "$gpg_files" ]; then
        log_warning "No .env.gpg files found in $dir"
        return 0
    fi

    local count=0
    while IFS= read -r gpg_file; do
        if [ -n "$gpg_file" ]; then
            local env_file="${gpg_file%.gpg}"
            log_info "Decrypting: $gpg_file -> $env_file"

            if gpg --quiet --output "$env_file" --decrypt "$gpg_file"; then
                log_success "Decrypted: $env_file"
                count=$((count + 1))
            else
                log_error "Failed to decrypt: $gpg_file"
            fi
        fi
    done <<< "$gpg_files"

    if [ $count -gt 0 ]; then
        log_success "Decrypted $count .env.gpg file(s)"
    fi
}

# Clean (remove) all .env files in the directory tree
clean_env_files() {
    local dir="$1"
    local force="$2"

    log_info "Looking for .env files to clean in: $dir"

    # Find all .env files
    local env_files
    env_files=$(find "$dir" -name ".env" -type f 2>/dev/null)

    if [ -z "$env_files" ]; then
        log_warning "No .env files found in $dir"
        return 0
    fi

    # List files to be deleted
    echo -e "${YELLOW}The following .env files will be deleted:${NC}"
    while IFS= read -r env_file; do
        if [ -n "$env_file" ]; then
            echo "  $env_file"
        fi
    done <<< "$env_files"

    # Ask for confirmation unless force flag is set
    if [ "$force" = false ]; then
        echo ""
        echo -n "Do you really want to delete these files? [y/N]: "
        read -r confirmation
        case "$confirmation" in
            [yY]|[yY][eE][sS])
                ;;
            *)
                log_info "Operation cancelled"
                return 0
                ;;
        esac
    fi

    # Delete files
    local count=0
    while IFS= read -r env_file; do
        if [ -n "$env_file" ]; then
            if rm "$env_file"; then
                log_success "Deleted: $env_file"
                count=$((count + 1))
            else
                log_error "Failed to delete: $env_file"
            fi
        fi
    done <<< "$env_files"

    log_success "Deleted $count .env file(s)"
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        --encrypt|-e)
            if [ -n "$MODE" ]; then
                log_error "Multiple modes specified"
                exit 1
            fi
            MODE="encrypt"
            shift
            ;;
        --decrypt|-d)
            if [ -n "$MODE" ]; then
                log_error "Multiple modes specified"
                exit 1
            fi
            MODE="decrypt"
            shift
            ;;
        --clean|-c)
            if [ -n "$MODE" ]; then
                log_error "Multiple modes specified"
                exit 1
            fi
            MODE="clean"
            shift
            ;;
        -f)
            FORCE=true
            shift
            ;;
        --recipient)
            if [ -z "$2" ]; then
                log_error "Recipient email is required"
                exit 1
            fi
            RECIPIENT="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [ -n "$DIRECTORY" ]; then
                log_error "Multiple directories specified"
                exit 1
            fi
            DIRECTORY="$1"
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$MODE" ]; then
    log_error "No mode specified"
    usage
    exit 1
fi

if [ -z "$DIRECTORY" ]; then
    log_error "No directory specified"
    usage
    exit 1
fi

if [ "$MODE" = "encrypt" ] && [ -z "$RECIPIENT" ]; then
    log_error "Recipient email is required for encryption"
    usage
    exit 1
fi

# Validate directory
if [ ! -d "$DIRECTORY" ]; then
    log_error "Directory does not exist: $DIRECTORY"
    exit 1
fi

# Convert to absolute path
DIRECTORY=$(cd "$DIRECTORY" && pwd)

# Execute the requested operation
case $MODE in
    encrypt)
        encrypt_env_files "$DIRECTORY"
        ;;
    decrypt)
        decrypt_env_files "$DIRECTORY"
        ;;
    clean)
        clean_env_files "$DIRECTORY" "$FORCE"
        ;;
    *)
        log_error "Invalid mode: $MODE"
        exit 1
        ;;
esac
