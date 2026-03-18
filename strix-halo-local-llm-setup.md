# Local LLM Coding Setup — AMD Strix Halo (128GB, Ryzen AI Max+ 395)

> Research date: March 2026
> Target: opencode + llama-server on Ryzen AI Max+ 395, 128GB unified RAM, RDNA 3.5 iGPU (40 CUs, ~215 GB/s bandwidth)

---

## Hardware Overview

The Ryzen AI Max+ 395 (Strix Halo) provides:
- ~215 GB/s memory bandwidth across 128GB LPDDR5x-8000 unified memory
- 40 RDNA 3.5 compute units (iGPU)
- Inference is **memory-bandwidth-bound** — higher quantization (Q8 vs Q4) costs RAM but improves quality with minimal throughput penalty
- MoE models are particularly well-suited — only a fraction of parameters are active per token

---

## Backend Decision: ROCm vs Vulkan

### Critical Finding: All Qwen3.5-series models require ROCm

Qwen3.5 architecture uses **GatedDeltaNet** ops that have missing Vulkan compute shaders on gfx1151 (llama.cpp issue #20354). This causes ~12 tok/s regardless of GPU power on Vulkan. ROCm is required until a Vulkan fix lands (PRs #20334 / #20282 — check their status).

| Metric | Vulkan + RADV | ROCm + rocWMMA + FA |
|---|---|---|
| Short prompt pp512 | ~884 t/s | ~986 t/s |
| tg128 token gen | ~52 t/s | ~51 t/s |
| Long ctx tg8192 | ~32 t/s (degrades) | ~51 t/s (stable) |
| Memory ceiling | ~105 GB | ~104 GB |
| Qwen3.5 support | ❌ (shader gap) | ✅ |

**Qwen3-Coder-Next** uses standard MoE Transformer (not GatedDeltaNet), so Vulkan may work — but ROCm is still preferred for the large model size.

---

## Prerequisites

### 1. Expand GTT memory pool (one-time, critical)

Without this, the iGPU can only address ~8–14 GB of your 128 GB.

```bash
sudo grubby --update-kernel=ALL --args='amdgpu.gttsize=131072 ttm.pages_limit=33554432'
```

### 2. ROCm environment variables

```bash
export ROCBLAS_USE_HIPBLASLT=1
export HIPBLASLT_TENSILE_LIBPATH=/opt/rocm/lib/hipblaslt/library
export GGML_CUDA_ENABLE_UNIFIED_MEMORY=ON
```

### 3. Build llama.cpp with ROCm + rocWMMA

```bash
cmake -B build -DGGML_HIP=ON -DGGML_HIP_ROCWMMA_FATTN=ON -DAMDGPU_TARGETS=gfx1151
cmake --build build --config Release -j 16
```

For Vulkan (Qwen3-Coder-Next or if Qwen3.5 Vulkan fix lands):
```bash
cmake -B build -DGGML_VULKAN=ON
cmake --build build --config Release -j 16
```

### 4. Verify memory before each launch

```bash
python gguf-vram-estimator.py /path/to/model.gguf --contexts 16384 32768 65536
```

ROCm ceiling on Strix Halo: ~104 GB. Monitor live with `amdgpu_top`.

---

## Model Recommendations

### Summary Table

| Model | Quant | RAM | SWE-bench | Speed | Best For |
|---|---|---|---|---|---|
| **Qwen3.5-9B** | Q8_0 | ~10 GB | — | ~80–120 tok/s | Fast edits, quick Q&A |
| **Qwen3.5-27B** | Q8_0 | ~28 GB | 72.4% | ~40–60 tok/s | Daily driver, highest SWE score |
| **Qwen3-Coder-Next 80B** | Q6_K | ~66 GB | 70.6% | ~20–35 tok/s | Agentic coding, 256K context |
| **Qwen3.5-122B-A10B** | Q4_K_M | ~72 GB | 72.0% | ~15–25 tok/s | Best tool-use / function calling |

### Models to skip (fully superseded)
- **Qwen2.5-Coder-32B** — superseded by everything above
- **Qwen3-30B-A3B** — superseded by Qwen3-Coder-Next at same active param count

### Recommended combos

**Speed + quality (most common use):**
- Qwen3.5-9B (~10 GB) + Qwen3.5-27B (~28 GB) = ~38 GB combined

**Agentic coding setup:**
- Qwen3.5-27B (~28 GB) + Qwen3-Coder-Next Q4_K_M (~46 GB) = ~74 GB combined

**Maximum capability:**
- Qwen3.5-122B-A10B Q4_K_M alone (~72 GB) — best tool-use, near memory ceiling

---

## Model Details

### Qwen3.5 Family (Feb–Mar 2026)

General multimodal models that benchmark extremely well on coding. No dedicated "Qwen3.5-Coder" variant exists yet.

| Model | Architecture | Released | Context | SWE-bench |
|---|---|---|---|---|
| Qwen3.5-397B-A17B | Hybrid MoE (GatedDeltaNet) | Feb 16, 2026 | 1M | — |
| Qwen3.5-122B-A10B | Hybrid MoE | Feb 24, 2026 | 1M | 72.0% |
| Qwen3.5-35B-A3B | Hybrid MoE | Feb 24, 2026 | 1M | 69.2% |
| Qwen3.5-27B | Dense | Feb 24, 2026 | 1M | **72.4%** |
| Qwen3.5-9B | Dense | Mar 2, 2026 | 1M | — |

Notable: **Qwen3.5-27B dense outscores Qwen3-Coder-Next** (72.4 vs 70.6%) on SWE-bench despite being a general model. The Qwen3.5-35B-A3B MoE underperforms its dense 27B sibling on coding — the sparse MoE design at this scale favors throughput over raw coding quality.

### Qwen3-Coder-Next (Feb 4, 2026)

Purpose-built agentic coding model, successor to Qwen2.5-Coder and Qwen3-Coder.

- Architecture: Standard MoE (80B total / 3B active per token)
- Context: 256K native, 1M via YaRN
- SWE-bench Verified: **70.6%** (#1 at release)
- SWE-rebench Pass@5: **64.6%** (#1 at release)
- Training: Agentic RL on executable tasks, environment interaction
- Formats: BF16, FP8, GGUF (Unsloth), MLX

#### Quantization options for 128GB Strix Halo

| Quant | Size | Notes |
|---|---|---|
| Q4_K_M | ~46 GB | Minimum recommended |
| Q6_K | ~66 GB | **Recommended** — near-lossless |
| Q8_0 | ~85 GB | Best quality, tight but fits |

---

## llama-server Launch Commands

### Common ROCm environment prefix (add to all commands)

```bash
ROCBLAS_USE_HIPBLASLT=1 \
HIPBLASLT_TENSILE_LIBPATH=/opt/rocm/lib/hipblaslt/library \
GGML_CUDA_ENABLE_UNIFIED_MEMORY=ON \
```

---

### Model 1: Qwen3.5-9B Q8_0 — Fast model (port 8083)

```bash
ROCBLAS_USE_HIPBLASLT=1 \
HIPBLASLT_TENSILE_LIBPATH=/opt/rocm/lib/hipblaslt/library \
GGML_CUDA_ENABLE_UNIFIED_MEMORY=ON \
llama-server \
  -m /path/to/Qwen3.5-9B-Q8_0.gguf \
  --host 0.0.0.0 --port 8083 \
  -ngl 999 \
  -c 32768 \
  -b 2048 -ub 512 \
  -fa \
  -t 8 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --no-mmap --mlock \
  --jinja \
  --reasoning-format deepseek \
  --reasoning-budget 0 \
  --parallel 1 --cont-batching
```

**Key flags:**
- `--reasoning-budget 0` — disables thinking entirely for instant responses
- `-b 2048 -ub 512` — latency-optimized, not throughput-optimized
- Expected: ~80–120+ tok/s

---

### Model 2: Qwen3.5-27B Q8_0 — Daily driver (port 8080)

```bash
ROCBLAS_USE_HIPBLASLT=1 \
HIPBLASLT_TENSILE_LIBPATH=/opt/rocm/lib/hipblaslt/library \
GGML_CUDA_ENABLE_UNIFIED_MEMORY=ON \
llama-server \
  -m /path/to/Qwen3.5-27B-Q8_0.gguf \
  --host 0.0.0.0 --port 8080 \
  -ngl 999 \
  -c 32768 \
  -b 4096 -ub 2048 \
  -fa \
  -t 12 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --no-mmap --mlock \
  --jinja \
  --reasoning-format deepseek \
  --parallel 1 --cont-batching
```

**Key flags:**
- Thinking is **on by default** — control per-request: `{"chat_template_kwargs": {"enable_thinking": false}}`
- Add `--reasoning-budget 0` to globally disable thinking for faster responses
- `-t 12` — matches physical P-core count; avoid hyperthreaded count for inference

---

### Model 3: Qwen3-Coder-Next 80B Q6_K — Agentic coding (port 8081)

```bash
ROCBLAS_USE_HIPBLASLT=1 \
HIPBLASLT_TENSILE_LIBPATH=/opt/rocm/lib/hipblaslt/library \
GGML_CUDA_ENABLE_UNIFIED_MEMORY=ON \
llama-server \
  -m /path/to/Qwen3-Coder-Next-80B-Q6_K.gguf \
  --host 0.0.0.0 --port 8081 \
  -ngl 999 \
  -c 32768 \
  -b 8192 -ub 2048 \
  -fa \
  -t 16 \
  --cache-type-k q8_0 \
  --cache-type-v f16 \
  --mlock \
  --jinja \
  --reasoning-format deepseek \
  --parallel 1 --cont-batching
```

**Key flags:**
- `-b 8192` — large batch dramatically improves MoE prompt processing (~3x reported)
- `--cache-type-v f16` — keep V cache at F16 for MoE quality; K cache at q8_0 is fine
- No `--no-mmap` — on UMA, `--no-mmap` causes double-allocation at this size
- Expected: ~20–35 tok/s generation

**If OOM (add expert offload to CPU):**
```bash
  -ngl 999 -ot "exps=CPU" -t 20
```
Offloads MoE router experts to CPU while attention stays on GPU. Efficient because only 3B params are active per forward pass.

---

### Model 4: Qwen3.5-122B-A10B Q4_K_M — Best tool-use (port 8082)

```bash
ROCBLAS_USE_HIPBLASLT=1 \
HIPBLASLT_TENSILE_LIBPATH=/opt/rocm/lib/hipblaslt/library \
GGML_CUDA_ENABLE_UNIFIED_MEMORY=ON \
llama-server \
  -m /path/to/Qwen3.5-122B-A10B-Q4_K_M.gguf \
  --host 0.0.0.0 --port 8082 \
  -ngl 999 \
  -c 16384 \
  -b 8192 -ub 2048 \
  -fa \
  -t 16 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --mlock \
  --jinja \
  --reasoning-format deepseek \
  --parallel 1 --cont-batching
```

**Key flags:**
- **No `--no-mmap`** — on UMA, causes double-allocation and halves usable memory at this size
- `-c 16384` — constrained by memory ceiling (~72 GB model). Test 32768 with estimator first
- `--cache-type-k/v q4_0` — most aggressive KV quant to maximize context; requires `-fa`
- `-b 8192` — critical for MoE prompt processing with potential CPU/GPU split

**If OOM:**
```bash
  -ngl 999 -ot "exps=CPU" -t 20
```

**To extend context to 32k (verify memory first):**
```bash
  -c 32768 --cache-type-k q4_0 --cache-type-v q4_0
  # Adds ~4 GB KV — verify with gguf-vram-estimator.py
```

---

## Settings Summary Table

| Model | Port | `-c` | `-b`/`-ub` | KV cache (k/v) | `-t` | `--no-mmap` |
|---|---|---|---|---|---|---|
| Qwen3.5-9B Q8_0 | 8083 | 32768 | 2048/512 | q8_0/q8_0 | 8 | ✅ |
| Qwen3.5-27B Q8_0 | 8080 | 32768 | 4096/2048 | q8_0/q8_0 | 12 | ✅ |
| Qwen3-Coder-Next 80B Q6_K | 8081 | 32768 | 8192/2048 | q8_0/f16 | 16 | ❌ |
| Qwen3.5-122B-A10B Q4_K_M | 8082 | 16384 | 8192/2048 | q4_0/q4_0 | 16 | ❌ |

All models: `-ngl 999`, `-fa`, `--mlock`, `--jinja`, `--reasoning-format deepseek`, `--parallel 1 --cont-batching`

---

## opencode Configuration

### Install opencode
```bash
curl -fsSL https://opencode.ai/install | bash
```

### `~/.config/opencode/opencode.json`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "llama-cpp/qwen3.5-27b",
  "provider": {
    "llama-cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama-server (local)",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1"
      },
      "models": {
        "qwen3.5-9b": {
          "name": "Qwen3.5-9B Q8 (fast)",
          "limit": { "context": 32768, "output": 8192 }
        },
        "qwen3.5-27b": {
          "name": "Qwen3.5-27B Q8 (daily driver)",
          "limit": { "context": 32768, "output": 16384 }
        },
        "qwen3-coder-next": {
          "name": "Qwen3-Coder-Next 80B Q6 (agentic)",
          "limit": { "context": 32768, "output": 32768 }
        },
        "qwen3.5-122b": {
          "name": "Qwen3.5-122B Q4 (tool-use)",
          "limit": { "context": 16384, "output": 8192 }
        }
      }
    }
  }
}
```

Use `/model` inside opencode to switch between models on the fly.

> **Note**: Each model runs on its own llama-server port. Update `baseURL` to point to the port of whichever server is running, or run multiple servers simultaneously and update the config per session.

---

## Multi-model Workflow

```
Fast edits / quick questions  →  Qwen3.5-9B (port 8083)   ~instant responses
Daily coding / architecture   →  Qwen3.5-27B (port 8080)  best SWE-bench score
Complex agentic tasks         →  Qwen3-Coder-Next (8081)  256K context, purpose-built
Function calling / agents     →  Qwen3.5-122B (port 8082)  dominates tool-use benchmarks
```

Switch inside opencode with `/model <name>`.

---

## Known Issues & Caveats

| Issue | Affected | Workaround |
|---|---|---|
| GatedDeltaNet missing Vulkan shaders (#20354) | All Qwen3.5 models | Use ROCm; check PRs #20334/#20282 for Vulkan fix |
| ROCm slow loading >64 GB (#15018) | Coder-Next, 122B | Expected behavior; just wait |
| KV cache allocated to host memory (#18011) | Large models at long ctx | Add `--no-kv-offload` as fallback |
| `--no-mmap` double-allocation on UMA | 80B+ models | Omit `--no-mmap` for large MoE models |
| `enable_thinking: false` not always respected (#20182) | Qwen3.5 | Use `--reasoning-budget 0` server-side instead |
| CPU inference regression for Qwen3-Coder-Next (#19480) | Coder-Next | Use GPU (ROCm); CPU path ~7.7 tok/s |
| Ollama vision mmproj issues | Qwen3.5 | Use llama-server directly, not Ollama |

---

## References

- [llm-tracker.info — Strix Halo GPU Performance](https://llm-tracker.info/AMD-Strix-Halo-(Ryzen-AI-Max+-395)-GPU-Performance)
- [kyuz0/amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes)
- [Qwen3-Coder-Next announcement (qwen.ai)](https://qwen.ai/blog?id=qwen3-coder-next)
- [Qwen3.5 announcement (qwen.ai)](https://qwen.ai/blog?id=qwen3.5)
- [llama.cpp issue #20354 — Vulkan GatedDeltaNet](https://github.com/ggml-org/llama.cpp/issues/20354)
- [llama.cpp issue #18011 — ROCm KV cache host memory](https://github.com/ggml-org/llama.cpp/issues/18011)
- [llama.cpp issue #15018 — ROCm slow loading >64GB](https://github.com/ggml-org/llama.cpp/issues/15018)
- [pablo-ross/strix-halo-gmktec-evo-x2](https://github.com/pablo-ross/strix-halo-gmktec-evo-x2)
- [MoE offload guide (DocShotgun)](https://huggingface.co/blog/Doctor-Shotgun/llamacpp-moe-offload-guide)
- [opencode docs](https://opencode.ai/docs)
- [Unsloth Qwen3-Coder-Next GGUF](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF)
