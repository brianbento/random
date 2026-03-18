#!/usr/bin/env bash
# setup-llama-bench.sh
# Sets up and runs llama-throughput-lab inside an AMD Strix Halo toolbox on Fedora 43

set -euo pipefail

# --- Configuration (edit these) ---
TOOLBOX_NAME="${TOOLBOX_NAME:-vulkan-radv}"
MODEL_PATH="${LLAMA_MODEL_PATH:-}"
LLAMA_PARALLEL="${LLAMA_PARALLEL:-16}"
LLAMA_N_PREDICT="${LLAMA_N_PREDICT:-512}"
LLAMA_MAX_TOKENS_LIST="${LLAMA_MAX_TOKENS_LIST:-128,256,512,1024}"
LLAMA_CONCURRENCY_LIST="${LLAMA_CONCURRENCY_LIST:-1,2,4,8,16,32,64}"
LLAMA_CTXSIZE_PER_SESSION="${LLAMA_CTXSIZE_PER_SESSION:-4096}"
LAB_DIR="${HOME}/llama-throughput-lab"
LAB_REPO="https://github.com/alexziskind1/llama-throughput-lab"
TOOLBOX_SCRIPT_URL="https://raw.githubusercontent.com/kyuz0/amd-strix-halo-toolboxes/main/refresh-toolboxes.sh"

# --- Helpers ---
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
die()   { echo "[ERROR] $*" >&2; exit 1; }

# --- Step 1: Check kernel boot params ---
check_kernel_params() {
    info "Checking kernel boot parameters..."
    local cmdline
    cmdline=$(cat /proc/cmdline)
    local missing=()
    [[ "$cmdline" == *"iommu=pt"* ]]                      || missing+=("iommu=pt")
    [[ "$cmdline" == *"amdgpu.gttsize=126976"* ]]         || missing+=("amdgpu.gttsize=126976")
    [[ "$cmdline" == *"ttm.pages_limit=32505856"* ]]      || missing+=("ttm.pages_limit=32505856")

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing kernel boot parameters: ${missing[*]}"
        warn "Add them to your bootloader config, e.g.:"
        warn "  sudo grubby --args='${missing[*]}' --update-kernel=ALL"
        warn "Then reboot before running inference. Continuing anyway..."
    else
        info "Kernel boot parameters OK."
    fi
}

# --- Step 2: Install host dependencies ---
install_host_deps() {
    info "Installing host dependencies (dialog, python3, git)..."
    local missing_pkgs=()
    command -v dialog &>/dev/null || missing_pkgs+=(dialog)
    command -v python3 &>/dev/null || missing_pkgs+=(python3)
    command -v git    &>/dev/null || missing_pkgs+=(git)
    command -v curl   &>/dev/null || missing_pkgs+=(curl)

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        sudo dnf install -y "${missing_pkgs[@]}"
    else
        info "Host dependencies already installed."
    fi
}

# --- Step 3: Set up the toolbox ---
setup_toolbox() {
    info "Setting up toolbox: ${TOOLBOX_NAME}..."
    if toolbox list 2>/dev/null | grep -q "^${TOOLBOX_NAME}$"; then
        info "Toolbox '${TOOLBOX_NAME}' already exists. Skipping."
    else
        info "Pulling and creating toolbox via refresh-toolboxes.sh..."
        curl -fsSL "${TOOLBOX_SCRIPT_URL}" | bash -s -- "${TOOLBOX_NAME}"
    fi
}

# --- Step 4: Clone llama-throughput-lab ---
clone_lab() {
    if [[ -d "${LAB_DIR}/.git" ]]; then
        info "llama-throughput-lab already cloned at ${LAB_DIR}, pulling latest..."
        git -C "${LAB_DIR}" pull --ff-only
    else
        info "Cloning llama-throughput-lab into ${LAB_DIR}..."
        git clone "${LAB_REPO}" "${LAB_DIR}"
    fi
}

# --- Step 5: Prompt for model path if not set ---
resolve_model_path() {
    if [[ -z "${MODEL_PATH}" ]]; then
        echo ""
        read -rp "Enter path to your GGUF model file: " MODEL_PATH
    fi
    [[ -f "${MODEL_PATH}" ]] || die "Model file not found: ${MODEL_PATH}"
    info "Using model: ${MODEL_PATH}"
}

# --- Step 6: (Optional) estimate VRAM ---
estimate_vram() {
    info "Running VRAM estimator inside toolbox..."
    toolbox run --container "${TOOLBOX_NAME}" \
        gguf-vram-estimator.py "${MODEL_PATH}" || warn "VRAM estimator failed (non-fatal)."
}

# --- Step 7: Write an inner launch script and run it inside the toolbox ---
run_benchmark() {
    local inner_script
    inner_script=$(mktemp /tmp/llama-bench-inner.XXXXXX.sh)
    chmod +x "${inner_script}"

    cat > "${inner_script}" <<INNER
#!/usr/bin/env bash
set -euo pipefail

export LLAMA_SERVER_BIN=\$(command -v llama-server 2>/dev/null || echo /usr/local/bin/llama-server)
export LLAMA_MODEL_PATH="${MODEL_PATH}"
export LLAMA_SERVER_ARGS="--flash-attn,--no-mmap"
export LLAMA_PARALLEL="${LLAMA_PARALLEL}"
export LLAMA_N_PREDICT="${LLAMA_N_PREDICT}"
export LLAMA_MAX_TOKENS_LIST="${LLAMA_MAX_TOKENS_LIST}"
export LLAMA_CONCURRENCY_LIST="${LLAMA_CONCURRENCY_LIST}"
export LLAMA_CTXSIZE_PER_SESSION="${LLAMA_CTXSIZE_PER_SESSION}"

cd "${LAB_DIR}"
echo "[INFO]  llama-server: \${LLAMA_SERVER_BIN}"
echo "[INFO]  Model:        \${LLAMA_MODEL_PATH}"
echo "[INFO]  Parallel:     \${LLAMA_PARALLEL}"
echo "[INFO]  Ctx/session:  \${LLAMA_CTXSIZE_PER_SESSION}"
echo ""
python3 run_llama_tests.py
INNER

    info "Launching benchmark inside toolbox '${TOOLBOX_NAME}'..."
    toolbox run --container "${TOOLBOX_NAME}" bash "${inner_script}"
    rm -f "${inner_script}"
}

# --- Main ---
main() {
    echo "======================================"
    echo " llama-throughput-lab on Strix Halo"
    echo " Toolbox: ${TOOLBOX_NAME}"
    echo "======================================"
    echo ""

    check_kernel_params
    install_host_deps
    setup_toolbox
    clone_lab
    resolve_model_path

    echo ""
    read -rp "Run VRAM estimator before benchmarking? [y/N] " run_vram
    [[ "${run_vram,,}" == "y" ]] && estimate_vram

    echo ""
    run_benchmark
}

main "$@"
