#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are available
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    if ! command -v nix-prefetch-url >/dev/null 2>&1; then
        missing_deps+=("nix-prefetch-url")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_error "Please install them before running this script"
        exit 1
    fi
}

# Platform mapping from Nix system to Koka release naming
declare -A PLATFORM_MAP=(
    ["x86_64-linux"]="linux-x64"
    ["aarch64-linux"]="linux-arm64"
    ["x86_64-darwin"]="macos-x64"
    ["aarch64-darwin"]="macos-arm64"
    ["x86_64-windows"]="windows-x64"
)

# Function to get all releases from GitHub API
get_releases() {
    print_status "Fetching releases from GitHub API..."
    curl -s "https://api.github.com/repos/koka-lang/koka/releases" | jq -r '.[].tag_name' | sort -V
}


# Function to compute SHA256 for a URL using nix-prefetch-url
compute_sha256() {
    local url="$1"
    print_status "Computing SHA256 for: $url" >&2
    
    local sha256
    sha256=$(nix-prefetch-url "$url" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$sha256" ]; then
        echo "$sha256"
    else
        print_error "Failed to compute SHA256 for $url" >&2
        return 1
    fi
}

# Function to generate entry for a single version
generate_version_entry() {
    local version="$1"
    local version_clean="${version#v}" # Remove 'v' prefix
    
    print_status "Processing version: $version" >&2
    
    # We'll include whatever platforms are available
    
    local version_json="{"
    local first=true
    
    for nix_platform in "${!PLATFORM_MAP[@]}"; do
        local koka_platform="${PLATFORM_MAP[$nix_platform]}"
        local url="https://github.com/koka-lang/koka/releases/download/${version}/koka-${version}-${koka_platform}.tar.gz"
        
        # Check if this platform's asset exists
        if ! curl -s -I "$url" | grep -q -E "(200|302)"; then
            print_status "Skipping platform $nix_platform ($koka_platform): asset not found" >&2
            continue
        fi
        
        print_status "Processing platform: $nix_platform ($koka_platform)" >&2
        
        local sha256
        if ! sha256=$(compute_sha256 "$url"); then
            print_error "Failed to get SHA256 for $nix_platform, skipping" >&2
            continue
        fi
        
        if [ "$first" = true ]; then
            first=false
        else
            version_json+=","
        fi
        
        version_json+="
    \"$nix_platform\": {
      \"url\": \"$url\",
      \"sha256\": \"$sha256\",
      \"version\": \"$version_clean\"
    }"
    done
    
    # Check if we found any platforms
    if [ "$first" = true ]; then
        print_warning "Skipping $version: no assets found for any platform" >&2
        return 1
    fi
    
    version_json+="
  }"
    
    echo "  \"$version_clean\": $version_json"
}

# Function to update sources.json
update_sources() {
    local max_versions="${1:-10}" # Default to 10 versions
    
    print_status "Updating sources.json with up to $max_versions versions..."
    
    local releases
    releases=$(get_releases)
    
    if [ -z "$releases" ]; then
        print_error "No releases found"
        return 1
    fi
    
    # Create temporary file for new sources.json
    local temp_file
    temp_file=$(mktemp)
    
    echo "{" > "$temp_file"
    
    local count=0
    local first=true
    
    # Process releases in reverse order (newest first)
    while IFS= read -r version; do
        if [ $count -ge $max_versions ]; then
            break
        fi
        
        local version_entry
        if version_entry=$(generate_version_entry "$version"); then
            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$temp_file"
            fi
            
            echo "$version_entry" >> "$temp_file"
            ((count++))
            print_success "Added version: $version"
        fi
    done <<< "$(echo "$releases" | tail -r)" # Reverse order using tail -r (macOS compatible)
    
    echo "" >> "$temp_file"
    echo "}" >> "$temp_file"
    
    # Validate JSON
    if jq empty "$temp_file" 2>/dev/null; then
        mv "$temp_file" sources.json
        print_success "Successfully updated sources.json with $count versions"
    else
        print_error "Generated JSON is invalid"
        rm -f "$temp_file"
        return 1
    fi
}

# Main function
main() {
    local max_versions=10
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--num-versions)
                max_versions="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -n, --num-versions NUM    Maximum number of versions to include (default: 10)"
                echo "  -h, --help               Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    print_status "Starting sources.json update process..."
    
    check_dependencies
    
    # Backup existing sources.json if it exists
    if [ -f sources.json ]; then
        cp sources.json sources.json.backup
        print_status "Backed up existing sources.json to sources.json.backup"
    fi
    
    if update_sources "$max_versions"; then
        print_success "Update completed successfully!"
        print_status "You can now run 'nix flake check' to validate the updated configuration"
    else
        print_error "Update failed!"
        if [ -f sources.json.backup ]; then
            mv sources.json.backup sources.json
            print_status "Restored backup"
        fi
        exit 1
    fi
}

# Run main function with all arguments
main "$@"