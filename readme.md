## llama-server: Local AI Inference Server

**Running Qwen3-Coder-30B locally with Vulkan GPU acceleration**

### The Setup

- **Hardware**: AMD Ryzen 7 8845HS (8C/16T) + Radeon 780M iGPU (gfx1103)
- **Model**: Qwen3-Coder-30B-A3B-Instruct (Q4_K_M, 18GB)
- **Backend**: Vulkan (Mesa RADV driver)
- **Performance**: 28 tokens/second with 50 GPU layers
- **Status**: Production-ready, stable

### The Journey

Initially deployed with ROCm/HIP for GPU acceleration, but the AMD gfx1103 integrated GPU had incomplete ROCm support - crashed constantly with SIGABRT. After troubleshooting (symlink attempts, library fixes), switched to Vulkan backend which works perfectly with the integrated GPU's RADV driver.

**Key discovery**: For AMD integrated GPUs (especially newer gfx1103), Vulkan > ROCm. Sweet spot is 50 GPU layers for this hardware configuration.

### Performance by Configuration

| GPU Layers | Speed | Notes |
|-----------|-------|-------|
| 0 (CPU-only) | 5 t/s | Too slow |
| 10 | 17 t/s | Conservative |
| **50** | **28 t/s** | **Optimal** ⭐ |
| 999 | Testing | Maximum offload |

### Quick Commands

```bash
# Status
systemctl status llama-server

# Test
curl http://localhost:8091/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"test"}],"max_tokens":20}'

# Logs
journalctl -u llama-server -f
```

### Documentation

- **Project**: [llama-server-deploy/README.md](./llama-server-deploy/README.md)
- **Complete Guide**: [README.md](../../README.md)
- **Quick Reference**: [QUICKSTART.md](../../QUICKSTART.md)
- **Migration Story**: [LLAMA_SERVER_FIXES.md](../../LLAMA_SERVER_FIXES.md)
- **Setup Script**: [setup-llama-vulkan-complete.sh](../../setup-llama-vulkan-complete.sh)

---

## Other Tools

- `.bmad-*` - Infrastructure automation tools
- `.claude/` - Claude Code configurations
- `AGENTS.md` - Agent setup docs

---

**Last Updated**: 2025-11-26
