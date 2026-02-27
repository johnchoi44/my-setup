#!/bin/bash

# =============================================================================
# Git Worktree Setup Script for ExcelsiorProduction
# =============================================================================
# This script automates:
#   1. Creating a new git worktree
#   2. Copying .env file from main repository
#   3. Symlinking .claude directory
#   4. Copying CLAUDE.md from main repository
#   5. Installing npm dependencies
#   6. Running baml:generate
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
WORKTREE_BASE="../ExcelsiorProduction.worktrees"
MAIN_REPO="$(git rev-parse --show-toplevel 2>/dev/null)"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_step() {
    echo -e "\n${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_header() {
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
}

usage() {
    echo "Usage: $(basename "$0") [branch-name] [options]"
    echo ""
    echo "If no branch-name is provided, interactive mode will prompt for input."
    echo ""
    echo "Options:"
    echo "  -s, --source <branch>  Source branch to base the new worktree on"
    echo "  -b, --base <path>      Custom worktree base directory (default: $WORKTREE_BASE)"
    echo "  -n, --no-install       Skip npm install and baml:generate"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                                    # Interactive mode"
    echo "  $(basename "$0") feature/new-dashboard              # Create from current branch"
    echo "  $(basename "$0") feature/new-dashboard -s main      # Create from main branch"
    echo "  $(basename "$0") bugfix/login-issue --source develop"
    echo "  $(basename "$0") testing --no-install"
    exit 1
}

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------

BRANCH=""
SKIP_INSTALL=false
SOURCE_BRANCH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--source)
            SOURCE_BRANCH="$2"
            shift 2
            ;;
        -b|--base)
            WORKTREE_BASE="$2"
            shift 2
            ;;
        -n|--no-install)
            SKIP_INSTALL=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            print_error "Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$BRANCH" ]; then
                BRANCH="$1"
            else
                print_error "Too many arguments"
                usage
            fi
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Interactive Prompt for Branch Name (if not provided)
# -----------------------------------------------------------------------------

INTERACTIVE_MODE=false

if [ -z "$BRANCH" ]; then
    INTERACTIVE_MODE=true
    
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Git Worktree Setup${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Show existing branches for reference
    echo -e "${BLUE}Existing local branches:${NC}"
    git branch --format='  %(refname:short)' 2>/dev/null | head -10
    BRANCH_COUNT=$(git branch --format='%(refname:short)' 2>/dev/null | wc -l)
    if [ "$BRANCH_COUNT" -gt 10 ]; then
        echo -e "  ${YELLOW}... and $((BRANCH_COUNT - 10)) more${NC}"
    fi
    echo ""
    
    # Show existing worktrees
    echo -e "${BLUE}Current worktrees:${NC}"
    git worktree list 2>/dev/null | while read line; do echo "  $line"; done
    echo ""
    
    # Get current branch
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
    
    # Prompt for source branch
    echo -e "${YELLOW}Which branch should the new worktree be based on?${NC}"
    echo -e "${CYAN}(Press Enter for default: ${CURRENT_BRANCH:-main})${NC}"
    echo ""
    read -p "Source branch: " INPUT_SOURCE_BRANCH
    
    # Default to current branch or main
    if [ -z "$INPUT_SOURCE_BRANCH" ]; then
        SOURCE_BRANCH="${CURRENT_BRANCH:-main}"
    else
        SOURCE_BRANCH="$INPUT_SOURCE_BRANCH"
    fi
    
    # Validate source branch exists
    if ! git show-ref --verify --quiet "refs/heads/$SOURCE_BRANCH" 2>/dev/null && \
       ! git show-ref --verify --quiet "refs/remotes/origin/$SOURCE_BRANCH" 2>/dev/null; then
        print_error "Source branch '$SOURCE_BRANCH' does not exist"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Using source branch: $SOURCE_BRANCH${NC}"
    echo ""
    
    # Prompt for new branch name
    echo -e "${YELLOW}Enter the name for the new worktree/branch:${NC}"
    echo -e "${CYAN}(Examples: feature/new-dashboard, bugfix/login-issue, testing)${NC}"
    echo ""
    read -p "New branch name: " BRANCH
    echo ""
    
    # Validate input
    if [ -z "$BRANCH" ]; then
        print_error "Branch name cannot be empty"
        exit 1
    fi
    
    # Confirm the setup
    echo -e "${BLUE}Summary:${NC}"
    echo -e "  Source branch: ${GREEN}$SOURCE_BRANCH${NC}"
    echo -e "  New branch:    ${GREEN}$BRANCH${NC}"
    echo -e "  Directory:     ${GREEN}$WORKTREE_BASE/$BRANCH${NC}"
    echo ""
    read -p "Continue? [Y/n] " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------

print_header "Worktree Setup: $BRANCH"

# Check if in a git repository
if [ -z "$MAIN_REPO" ]; then
    print_error "Not in a git repository!"
    exit 1
fi

print_success "Main repository: $MAIN_REPO"

# Use branch name directly for nested folder structure (bugfix/issue-123 → bugfix/issue-123/)
DIR_NAME="$BRANCH"
WORKTREE_PATH="$WORKTREE_BASE/$DIR_NAME"

# Create worktree base directory if it doesn't exist
mkdir -p "$WORKTREE_BASE"

# Convert to absolute path (fixes cd issues later in the script)
WORKTREE_BASE="$(cd "$WORKTREE_BASE" && pwd)"
WORKTREE_PATH="$WORKTREE_BASE/$DIR_NAME"

# Check if worktree already exists
if [ -d "$WORKTREE_PATH" ]; then
    print_error "Worktree already exists at: $WORKTREE_PATH"
    echo "  To remove it: git worktree remove --force $WORKTREE_PATH"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 1: Create Worktree
# -----------------------------------------------------------------------------

print_step "Creating worktree..."

# Create parent directories for nested structure (e.g., bugfix/ for bugfix/issue-123)
mkdir -p "$(dirname "$WORKTREE_PATH")"

# Check if the new branch already exists
if git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    # Branch already exists locally - use it directly
    git worktree add "$WORKTREE_PATH" "$BRANCH"
    print_success "Created worktree from existing local branch: $BRANCH"
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH" 2>/dev/null; then
    # Remote branch exists, track it
    git worktree add --track -b "$BRANCH" "$WORKTREE_PATH" "origin/$BRANCH"
    print_success "Created worktree tracking remote branch: origin/$BRANCH"
elif [ -n "$SOURCE_BRANCH" ]; then
    # Create new branch from specified source branch (interactive mode)
    git worktree add -b "$BRANCH" "$WORKTREE_PATH" "$SOURCE_BRANCH"
    print_success "Created worktree with new branch '$BRANCH' based on '$SOURCE_BRANCH'"
else
    # Non-interactive mode: create from current HEAD
    git worktree add -b "$BRANCH" "$WORKTREE_PATH"
    print_success "Created worktree with new branch: $BRANCH"
fi

# -----------------------------------------------------------------------------
# Step 2: Copy .env File
# -----------------------------------------------------------------------------

print_step "Copying environment files..."

ENV_COPIED=false

# Copy .env
if [ -f "$MAIN_REPO/.env" ]; then
    cp "$MAIN_REPO/.env" "$WORKTREE_PATH/.env"
    print_success "Copied .env"
    ENV_COPIED=true
else
    print_warning ".env not found in main repository"
fi

# Copy .env.local if exists
if [ -f "$MAIN_REPO/.env.local" ]; then
    cp "$MAIN_REPO/.env.local" "$WORKTREE_PATH/.env.local"
    print_success "Copied .env.local"
    ENV_COPIED=true
fi

# Copy any other .env.* files (like .env.development, .env.production)
for env_file in "$MAIN_REPO"/.env.*; do
    [ -f "$env_file" ] || continue
    filename=$(basename "$env_file")
    cp "$env_file" "$WORKTREE_PATH/$filename"
    print_success "Copied $filename"
    ENV_COPIED=true
done

if [ "$ENV_COPIED" = false ]; then
    print_warning "No .env files found to copy"
fi

# Set worktree title for browser tab
echo "" >> "$WORKTREE_PATH/.env"
echo "# Worktree browser tab title" >> "$WORKTREE_PATH/.env"
echo "WORKTREE_TITLE=$BRANCH" >> "$WORKTREE_PATH/.env"
print_success "Set WORKTREE_TITLE=$BRANCH in .env"

# -----------------------------------------------------------------------------
# Step 3: Symlink .claude Directory
# -----------------------------------------------------------------------------

print_step "Symlinking .claude directory..."

if [ -d "$MAIN_REPO/.claude" ]; then
    ln -s "$MAIN_REPO/.claude" "$WORKTREE_PATH/.claude"
    print_success "Symlinked .claude → $MAIN_REPO/.claude"
else
    print_warning ".claude directory not found in main repository"
fi

# -----------------------------------------------------------------------------
# Step 4: Copy CLAUDE.md
# -----------------------------------------------------------------------------

print_step "Copying CLAUDE.md..."

if [ -f "$MAIN_REPO/CLAUDE.md" ]; then
    cp "$MAIN_REPO/CLAUDE.md" "$WORKTREE_PATH/CLAUDE.md"
    print_success "Copied CLAUDE.md"
else
    print_warning "CLAUDE.md not found in main repository"
fi

# -----------------------------------------------------------------------------
# Step 5: Install Dependencies
# -----------------------------------------------------------------------------

if [ "$SKIP_INSTALL" = true ]; then
    print_step "Skipping npm install (--no-install flag)"
else
    print_step "Installing npm dependencies..."
    
    cd "$WORKTREE_PATH"
    
    if [ -f "package.json" ]; then
        npm install --legacy-peer-deps
        print_success "npm install completed"
    else
        print_warning "No package.json found, skipping npm install"
    fi
fi

# -----------------------------------------------------------------------------
# Step 6: Run BAML Generate
# -----------------------------------------------------------------------------

if [ "$SKIP_INSTALL" = true ]; then
    print_step "Skipping baml:generate (--no-install flag)"
else
    print_step "Running baml:generate..."
    
    cd "$WORKTREE_PATH"
    
    # Check if the script exists in package.json
    if grep -q '"baml:generate"' package.json 2>/dev/null; then
        npm run baml:generate
        print_success "baml:generate completed"
    else
        print_warning "baml:generate script not found in package.json, skipping"
    fi
fi

# -----------------------------------------------------------------------------
# Done!
# -----------------------------------------------------------------------------

print_header "Setup Complete!"

echo -e "
${GREEN}Worktree created successfully!${NC}

${CYAN}Location:${NC} $WORKTREE_PATH
${CYAN}Branch:${NC}   $BRANCH

${YELLOW}To enter the worktree, run:${NC}

    cd $WORKTREE_PATH

${YELLOW}Or copy this command:${NC}

    cd $(cd "$WORKTREE_PATH" && pwd)

${YELLOW}To list all worktrees:${NC}

    git worktree list

${YELLOW}To remove this worktree later:${NC}

    git worktree remove $WORKTREE_PATH
"

# -----------------------------------------------------------------------------
# Optional: Auto-enter worktree (only works if script is sourced)
# -----------------------------------------------------------------------------

# Export for potential sourcing
export WORKTREE_PATH
