#!/usr/bin/env bash
# install-rocm7-llama.sh
# Installs ROCm 7.x nightlies + llama.cpp (gfx1151 / Strix Halo) on bare-metal Fedora 43
set -euo pipefail

ROCM_MAJOR_VER=7
GFX=gfx1151
ROCM_PATH=/opt/rocm-7.0
LLAMA_REPO=https://github.com/ggerganov/llama.cpp.git
LLAMA_BRANCH=master

# ── 1. System packages ────────────────────────────────────────────────────────
echo "==> Installing build dependencies..."
sudo dnf -y --nodocs --setopt=install_weak_deps=False install \
  make gcc cmake lld clang clang-devel compiler-rt libcurl-devel \
  radeontop git vim patch curl ninja-build tar xz aria2c \
  libatomic libstdc++ libgcc procps-ng ca-certificates bash
sudo dnf clean all

# ── 2. Download latest ROCm 7.x nightly tarball ───────────────────────────────
echo "==> Finding latest ROCm nightly tarball for ${GFX}..."
BASE="https://therock-nightly-tarball.s3.amazonaws.com"
PREFIX="therock-dist-linux-${GFX}-${ROCM_MAJOR_VER}"
KEY="$(curl -s "${BASE}?list-type=2&prefix=${PREFIX}" \
  | tr '<' '\n' \
  | grep -o "therock-dist-linux-${GFX}-${ROCM_MAJOR_VER}\..*\.tar\.gz" \
  | sort -V | tail -n1)"
echo "==> Latest tarball: ${KEY}"

TMPDIR="$(mktemp -d)"
aria2c -x 16 -s 16 -j 16 --file-allocation=none "${BASE}/${KEY}" -o "${TMPDIR}/therock.tar.gz"

# ── 3. Extract ROCm ───────────────────────────────────────────────────────────
echo "==> Extracting ROCm to ${ROCM_PATH}..."
sudo mkdir -p "${ROCM_PATH}"
sudo tar xzf "${TMPDIR}/therock.tar.gz" -C "${ROCM_PATH}" --strip-components=1
rm -rf "${TMPDIR}"

# ── 4. Environment profile ────────────────────────────────────────────────────
echo "==> Writing /etc/profile.d/rocm.sh..."
sudo tee /etc/profile.d/rocm.sh > /dev/null <<'EOF'
export ROCM_PATH=/opt/rocm-7.0
export HIP_PLATFORM=amd
export HIP_PATH=/opt/rocm-7.0
export HIP_CLANG_PATH=/opt/rocm-7.0/llvm/bin
export HIP_INCLUDE_PATH=/opt/rocm-7.0/include
export HIP_LIB_PATH=/opt/rocm-7.0/lib
export HIP_DEVICE_LIB_PATH=/opt/rocm-7.0/lib/llvm/amdgcn/bitcode
export PATH="$ROCM_PATH/bin:$HIP_CLANG_PATH:$PATH"
export LD_LIBRARY_PATH="$HIP_LIB_PATH:$ROCM_PATH/lib:$ROCM_PATH/lib64:$ROCM_PATH/llvm/lib"
export LIBRARY_PATH="$HIP_LIB_PATH:$ROCM_PATH/lib:$ROCM_PATH/lib64"
export CPATH="$HIP_INCLUDE_PATH"
export PKG_CONFIG_PATH="$ROCM_PATH/lib/pkgconfig"
EOF
sudo chmod +x /etc/profile.d/rocm.sh

# Source for the remainder of this script
# shellcheck source=/dev/null
source /etc/profile.d/rocm.sh

# ── 5. Build llama.cpp ────────────────────────────────────────────────────────
echo "==> Cloning llama.cpp (${LLAMA_BRANCH})..."
sudo mkdir -p /opt/llama.cpp
sudo chown "$(id -u):$(id -g)" /opt/llama.cpp
git clone -b "${LLAMA_BRANCH}" --single-branch --recursive "${LLAMA_REPO}" /opt/llama.cpp
cd /opt/llama.cpp
git clean -xdf
git submodule update --recursive

echo "==> Building llama.cpp with HIP (${GFX})..."
cmake -S . -B build \
  -DGGML_HIP=ON \
  -DAMDGPU_TARGETS="${GFX}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_RPC=ON \
  -DLLAMA_HIP_UMA=ON
cmake --build build --config Release -- -j"$(nproc)"
sudo cmake --install build --config Release

# Copy RPC server binaries explicitly (install may not include them)
sudo cp /opt/llama.cpp/build/bin/rpc-* /usr/local/bin/ 2>/dev/null || true

# ── 6. Trim static libs / headers from ROCm to save space (optional) ─────────
echo "==> Removing ROCm static libs and headers to save disk space..."
sudo find "${ROCM_PATH}" -type f -name '*.a' -delete
sudo rm -rf \
  "${ROCM_PATH}/include" \
  "${ROCM_PATH}/share" \
  "${ROCM_PATH}/llvm/include" \
  "${ROCM_PATH}/llvm/share"

# ── 7. ldconfig for /usr/local libs ──────────────────────────────────────────
echo "==> Configuring ldconfig..."
echo "/usr/local/lib"   | sudo tee    /etc/ld.so.conf.d/local.conf > /dev/null
echo "/usr/local/lib64" | sudo tee -a /etc/ld.so.conf.d/local.conf > /dev/null
sudo ldconfig

echo ""
echo "==> Done! Log out and back in (or run: source /etc/profile.d/rocm.sh)"
echo "    to activate the ROCm environment."
echo "    Test with: llama-cli --version"
