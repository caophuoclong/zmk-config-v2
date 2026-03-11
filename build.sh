#!/usr/bin/env bash
set -euo pipefail

# ── ZMK Local Build Script for Sofle (Nice Nano v2 + Nice OLED) ─────────
# Builds .uf2 firmware files locally so you don't need to push to GitHub.
#
# Usage:
#   ./build.sh              # Build both halves
#   ./build.sh left         # Build left half only
#   ./build.sh right        # Build right half only
#   ./build.sh setup        # First-time setup (clone ZMK + install deps)
#   ./build.sh clean        # Remove build artifacts
#
# After building, .uf2 files are copied to ./firmware/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo $SCRIPT_DIR
ZMK_DIR="$SCRIPT_DIR/.zmk"
FIRMWARE_DIR="$SCRIPT_DIR/firmware"

BOARD="nice_nano"
LEFT_SHIELDS="kyria_left nice_view_adapter nice_view_custom"
RIGHT_SHIELDS="kyria_right nice_view_adapter nice_view_custom"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Check prerequisites ─────────────────────────────────────────────────
check_deps() {
    local missing=()
    for cmd in cmake ninja dtc python3 pip3 west; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install them with:"
        echo "  brew install cmake ninja dtc python3"
        echo "  pip3 install west"
        echo ""
        echo "Then run: ./build.sh setup"
        exit 1
    fi
}

# ── First-time setup ────────────────────────────────────────────────────
do_setup() {
    info "Setting up ZMK build environment..."
    check_deps

    if [[ -d "$ZMK_DIR" ]]; then
        warn "$ZMK_DIR already exists. Remove it first if you want a fresh setup."
        warn "  rm -rf $ZMK_DIR"
        exit 1
    fi

    mkdir -p "$ZMK_DIR"
    cd "$ZMK_DIR"
    cp -r "$SCRIPT_DIR/config" ./
    cp "$SCRIPT_DIR/build.yaml" ./
    info "Initializing west workspace from zmk-config manifest..."
    west init -l "$ZMK_DIR/config"
    west update

    info "Installing Zephyr SDK requirements..."
    cp "$SCRIPT_DIR/zephyr/module.yml" ./
    pip3 install -r ./zephyr/scripts/requirements.txt

    info "Exporting Zephyr CMake package..."
    west zephyr-export

    ok "Setup complete! You can now run: ./build.sh"
}

# ── Build one side ──────────────────────────────────────────────────────
build_side() {
    local side="$1"
    local shields="$2"

    info "Building ${side} half (board=${BOARD}, shields=\"${shields}\")..."

    cd "$ZMK_DIR"
    cp -r "$SCRIPT_DIR/config" ./
    cp "$SCRIPT_DIR/build.yaml" ./
    cp "$SCRIPT_DIR/zephyr/module.yml" ./zephyr/module.yml


    west build -s zmk/app -p -b "$BOARD" -d "build/${side}" -- \
        -DSHIELD="${shields}" \
        -DZMK_CONFIG="$SCRIPT_DIR/config"

    mkdir -p "$FIRMWARE_DIR"
    cp "build/${side}/zephyr/zmk.uf2" "$FIRMWARE_DIR/sofle_${side}.uf2"

    ok "Built: firmware/sofle_${side}.uf2"
}

# ── Clean builds ────────────────────────────────────────────────────────
do_clean() {
    info "Cleaning build artifacts..."
    rm -rf "$ZMK_DIR/build" "$FIRMWARE_DIR"
    ok "Clean complete."
}

# ── Flash instructions ──────────────────────────────────────────────────
print_flash_instructions() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Build complete! Firmware files:${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    ls -lh "$FIRMWARE_DIR"/*.uf2 2>/dev/null || true
    echo ""
    echo "To flash:"
    echo "  1. Connect one half via USB"
    echo "  2. Double-press the reset button to enter bootloader"
    echo "  3. A USB drive named NICENANO will appear"
    echo "  4. Copy the matching .uf2 file to the drive:"
    echo "       cp firmware/sofle_left.uf2 /Volumes/NICENANO/"
    echo "       cp firmware/sofle_right.uf2 /Volumes/NICENANO/"
    echo "  5. The controller will reboot automatically"
    echo "  6. Repeat for the other half"
    echo ""
}

# ── Main ────────────────────────────────────────────────────────────────
main() {
    local target="${1:-both}"

    case "$target" in
        setup)
            do_setup
            ;;
        clean)
            do_clean
            ;;
        left)
            check_deps
            [[ ! -d "$ZMK_DIR/zmk" ]] && { err "Run './build.sh setup' first."; exit 1; }
            build_side "left" "$LEFT_SHIELDS"
            print_flash_instructions
            ;;
        right)
            check_deps
            [[ ! -d "$ZMK_DIR/zmk" ]] && { err "Run './build.sh setup' first."; exit 1; }
            build_side "right" "$RIGHT_SHIELDS"
            print_flash_instructions
            ;;
        both)
            check_deps
            [[ ! -d "$ZMK_DIR/zmk" ]] && { err "Run './build.sh setup' first."; exit 1; }
            build_side "left" "$LEFT_SHIELDS"
            build_side "right" "$RIGHT_SHIELDS"
            print_flash_instructions
            ;;
        *)
            echo "Usage: ./build.sh [setup|left|right|both|clean]"
            exit 1
            ;;
    esac
}

main "$@"
