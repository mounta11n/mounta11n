#!/usr/bin/env bash

# Exit on error for critical operations
set -e

# ==============================================================================
# SSH Key Setup Script - Enhanced Version
# ==============================================================================
# Fetches SSH public keys from GitHub and adds them to authorized_keys
# Features: retry logic, fallbacks, backup, notifications, duplicate prevention
# ==============================================================================

# Configuration
readonly DEFAULT_GITHUB_USER="mounta11n"
readonly DEFAULT_NTFY_TOPIC="inbox"
readonly RETRY_COUNT=3
readonly RETRY_DELAY=2
readonly CONNECT_TIMEOUT=10
readonly MAX_TIME=30
readonly SSH_DIR="$HOME/.ssh"
readonly AUTH_KEYS_FILE="$SSH_DIR/authorized_keys"

# Parse arguments
GITHUB_USER="${1:-$DEFAULT_GITHUB_USER}"
NTFY_TOPIC="${2:-$DEFAULT_NTFY_TOPIC}"

# Color codes for output
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'

# Humorous goodbyes for notifications
GOODBYES=(
    "May your deploys be swift and your bugs be few! 🚀"
    "SSH-ing into the future, one key at a time! 🔑"
    "Your keys are now in place. Time for some coffee! ☕"
    "Access granted! Now go build something awesome! 💪"
    "Keys deployed successfully. You're all set, legend! 🎉"
    "Connection established. Welcome to the party! 🎊"
)

# ==============================================================================
# Logging Functions
# ==============================================================================

log_info() {
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*"
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# Get random goodbye message
get_random_goodbye() {
    local size=${#GOODBYES[@]}
    local index=$((RANDOM % size))
    echo "${GOODBYES[$index]}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ==============================================================================
# HTTP Fetching with Fallback
# ==============================================================================

fetch_url() {
    local url="$1"
    local attempt=1
    local result=""
    
    while [ $attempt -le $RETRY_COUNT ]; do
        if [ $attempt -gt 1 ]; then
            log_info "Retry attempt $attempt of $RETRY_COUNT..."
            sleep $RETRY_DELAY
        fi
        
        # Try curl first
        if command_exists curl; then
            result=$(curl -s --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIME "$url" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                echo "$result"
                return 0
            fi
        # Fallback to wget
        elif command_exists wget; then
            result=$(wget -q --timeout=$MAX_TIME --tries=1 -O - "$url" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                echo "$result"
                return 0
            fi
        else
            log_error "Neither curl nor wget is available"
            return 1
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Failed to fetch URL after $RETRY_COUNT attempts: $url"
    return 1
}

# ==============================================================================
# JSON Parsing with Fallback
# ==============================================================================

parse_github_keys() {
    local json_data="$1"
    
    # Try jq first if available
    if command_exists jq; then
        local result=$(echo "$json_data" | jq -r '.[].key' 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
    fi
    
    # Fallback to grep/sed parsing
    # Note: This is a simple fallback for basic JSON. May not handle all edge cases.
    log_warn "jq not found, using grep/sed fallback for JSON parsing"
    local result=$(echo "$json_data" | grep '"key"' | sed 's/.*"key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    
    # Validate that extracted keys look like SSH keys
    if [ -n "$result" ] && echo "$result" | grep -qE "^(ssh-|ecdsa-|sk-)"; then
        echo "$result"
        return 0
    else
        log_error "Failed to parse valid SSH keys from JSON response"
        return 1
    fi
}

# ==============================================================================
# SSH Key Management
# ==============================================================================

setup_ssh_directory() {
    if [ ! -d "$SSH_DIR" ]; then
        log_info "Creating SSH directory: $SSH_DIR"
        mkdir -p "$SSH_DIR"
    fi
    
    # Set correct permissions
    chmod 700 "$SSH_DIR"
    log_info "Set permissions on $SSH_DIR to 700"
    
    # Create authorized_keys if it doesn't exist
    if [ ! -f "$AUTH_KEYS_FILE" ]; then
        touch "$AUTH_KEYS_FILE"
        log_info "Created $AUTH_KEYS_FILE"
    fi
    
    chmod 600 "$AUTH_KEYS_FILE"
    log_info "Set permissions on $AUTH_KEYS_FILE to 600"
}

backup_authorized_keys() {
    if [ -f "$AUTH_KEYS_FILE" ] && [ -s "$AUTH_KEYS_FILE" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${AUTH_KEYS_FILE}.backup_${timestamp}"
        cp "$AUTH_KEYS_FILE" "$backup_file"
        log_info "Created backup: $backup_file"
    fi
}

is_key_present() {
    local key="$1"
    [ -f "$AUTH_KEYS_FILE" ] && grep -qF "$key" "$AUTH_KEYS_FILE"
}

add_keys() {
    local keys="$1"
    local new_keys_count=0
    local duplicate_count=0
    
    while IFS= read -r key; do
        # Skip empty lines
        [ -z "$key" ] && continue
        
        if is_key_present "$key"; then
            duplicate_count=$((duplicate_count + 1))
        else
            echo "$key" >> "$AUTH_KEYS_FILE"
            new_keys_count=$((new_keys_count + 1))
        fi
    done <<< "$keys"
    
    log_info "Added $new_keys_count new key(s)"
    if [ $duplicate_count -gt 0 ]; then
        log_info "Skipped $duplicate_count duplicate key(s)"
    fi
    
    # Count total keys - more comprehensive pattern for various SSH key types
    local total_keys=$(grep -cE "^(ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ecdsa-sha2-nistp256|sk-ssh-ed25519)" "$AUTH_KEYS_FILE" 2>/dev/null || echo "0")
    log_info "Total keys in authorized_keys: $total_keys"
    
    echo "$new_keys_count"
}

# ==============================================================================
# ntfy.sh Notification
# ==============================================================================
# SECURITY NOTE: Notifications include server information (hostname, IP, system).
# Only use this feature with private ntfy topics if you want to keep server details confidential.
# Public topics like "inbox" will expose this information.

send_notification() {
    local github_user="$1"
    local new_keys_count="$2"
    local topic="$3"
    
    # Don't fail the script if notification fails
    set +e
    
    log_info "Sending notification to ntfy.sh topic: $topic"
    
    # Gather system information
    # Note: This information may be sensitive. Use private topics for production servers.
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    
    # Optional: Fetch public IP (requires external service call)
    # Set to "hidden" by default for security. Uncomment the line below to include it.
    local public_ip="hidden"
    # local public_ip=$(fetch_url "https://api.ipify.org" 2>/dev/null || echo "unknown")
    
    local system_info=$(uname -a 2>/dev/null || echo "unknown")
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC" 2>/dev/null)
    local goodbye=$(get_random_goodbye)
    
    # Build notification message
    local message="SSH Keys Deployed Successfully! 🎉

GitHub User: $github_user
New Keys Added: $new_keys_count
Server: $hostname
Public IP: $public_ip
System: $system_info
Time: $timestamp

$goodbye"
    
    # Send notification
    if command_exists curl; then
        curl -s --connect-timeout 5 --max-time 10 \
            -H "Title: SSH Keys Deployed" \
            -H "Priority: default" \
            -H "Tags: white_check_mark,key" \
            -d "$message" \
            "https://ntfy.sh/$topic" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log_info "Notification sent successfully"
        else
            log_warn "Failed to send notification (non-critical)"
        fi
    elif command_exists wget; then
        wget -q --timeout=10 --tries=1 \
            --header="Title: SSH Keys Deployed" \
            --header="Priority: default" \
            --header="Tags: white_check_mark,key" \
            --post-data="$message" \
            -O /dev/null \
            "https://ntfy.sh/$topic" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log_info "Notification sent successfully"
        else
            log_warn "Failed to send notification (non-critical)"
        fi
    else
        log_warn "Cannot send notification: neither curl nor wget available"
    fi
    
    # Re-enable exit on error
    set -e
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    log_info "Starting SSH key setup for GitHub user: $GITHUB_USER"
    
    # Setup SSH directory and permissions
    setup_ssh_directory
    
    # Backup existing authorized_keys
    backup_authorized_keys
    
    # Fetch keys from GitHub
    log_info "Fetching SSH keys from GitHub API..."
    local github_api_url="https://api.github.com/users/$GITHUB_USER/keys"
    local json_data=$(fetch_url "$github_api_url")
    
    if [ -z "$json_data" ]; then
        log_error "Failed to fetch keys from GitHub"
        exit 1
    fi
    
    # Parse JSON and extract keys
    log_info "Parsing SSH keys..."
    local keys=$(parse_github_keys "$json_data")
    
    if [ -z "$keys" ]; then
        log_error "No keys found or failed to parse JSON"
        exit 1
    fi
    
    # Add keys to authorized_keys
    log_info "Adding keys to authorized_keys..."
    local new_keys_count=$(add_keys "$keys")
    
    # Send notification
    send_notification "$GITHUB_USER" "$new_keys_count" "$NTFY_TOPIC"
    
    log_info "SSH key setup completed successfully! ✅"
}

# Run main function
main
