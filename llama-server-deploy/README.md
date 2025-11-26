# llama.cpp Server Deployment

**Production LLM inference server with Vulkan GPU acceleration for AMD integrated graphics**

[![Status](https://img.shields.io/badge/status-production-brightgreen)]()
[![Backend](https://img.shields.io/badge/backend-Vulkan-blue)]()
[![Performance](https://img.shields.io/badge/performance-28%20tokens%2Fs-orange)]()
[![GPU](https://img.shields.io/badge/GPU-AMD%20gfx1103-red)]()

---

## 📋 Project Brief

This is a **production-ready deployment** of llama.cpp inference server optimized for **AMD Ryzen 7 8845HS** with **Radeon 780M integrated GPU** (gfx1103). The server runs **Qwen3-Coder-30B** model with **Vulkan GPU acceleration**, achieving **28 tokens/second** with stable performance.

### What This Repo Contains

- ✅ **Vulkan-optimized llama.cpp build** (replaces ROCm/HIP)
- ✅ **Systemd service configuration** with auto-restart
- ✅ **Nginx reverse proxy** with SSL/TLS and authentication
- ✅ **Management scripts** for deployment and monitoring
- ✅ **Complete documentation** of migration from ROCm to Vulkan

### Key Achievement

**Fixed critical issue**: Migrated from crashing ROCm backend to stable Vulkan backend, achieving 28 tokens/s with 50 GPU layers offloaded to integrated GPU.

---

## 📚 Documentation

### Primary Documentation (Complete Guides)

Located in `~/` directory - comprehensive documentation with full details:

| Document | Purpose | What's Inside |
|----------|---------|---------------|
| **[~/README.md](../../../README.md)** | Main documentation hub | Complete overview, architecture, benchmarks, API usage |
| **[~/QUICKSTART.md](../../../QUICKSTART.md)** | Quick reference guide | 5-minute setup, essential commands, troubleshooting |
| **[~/LLAMA_SERVER_FIXES.md](../../../LLAMA_SERVER_FIXES.md)** | Troubleshooting history | ROCm→Vulkan migration, problem analysis, solutions |
| **[~/setup-llama-vulkan-complete.sh](../../../setup-llama-vulkan-complete.sh)** | Automated setup script | One-command installation and testing |

### Repository Files (This Directory)

| File | Purpose | Status |
|------|---------|--------|
| `README.md` | This file - repository overview | Current |
| `manage.sh` | Server management utility | Active |
| `deploy.sh` | Original ROCm deployment | Deprecated |
| `preflight-check.sh` | System requirements check | Active |
| `config.env` | Deployment configuration | Active |
| `llama.cpp/build-vulkan/` | Vulkan build (production) | ✅ Active |
| `llama.cpp/build/` | ROCm build (old) | ❌ Deprecated |

---

## ⚠️ Important: Vulkan Backend (Nov 26, 2025)

This deployment **switched from ROCm to Vulkan** due to AMD gfx1103 GPU incompatibility with ROCm.

| Aspect | Before (ROCm) | After (Vulkan) |
|--------|---------------|----------------|
| **Status** | ❌ Crashing (SIGABRT) | ✅ Stable |
| **Performance** | N/A (crashed) | 28 tokens/s |
| **GPU Support** | Incomplete (missing libraries) | Native (RADV driver) |
| **Reliability** | 0% (constant crashes) | 100% (no crashes) |

**Migration Details**: See [LLAMA_SERVER_FIXES.md](../../../LLAMA_SERVER_FIXES.md)

---

## 🚀 Quick Start

### Fastest Setup (Recommended)

```bash
cd ~
sudo bash setup-llama-vulkan-complete.sh
```

**Time**: 10-15 minutes | **What it does**: Install Vulkan, build llama.cpp, configure service, test

### Check Current Status

```bash
# Service status
systemctl status llama-server

# Test inference
curl -s http://localhost:8091/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"max_tokens":20}'
```

### Management

```bash
./manage.sh status    # Check all services
./manage.sh restart   # Restart llama-server
./manage.sh logs      # View logs
./manage.sh gpu       # Monitor GPU usage
```

---

## 📊 Performance Summary

### Current Configuration

- **Backend**: Vulkan (RADV PHOENIX driver)
- **GPU**: AMD Radeon 780M (gfx1103, RDNA 3)
- **Model**: Qwen3-Coder-30B-A3B-Instruct-Q4_K_M (18GB)
- **GPU Layers**: 50 (optimized)
- **Performance**: 28 tokens/second

### Performance by GPU Layers

| Layers | Speed | Status | Recommendation |
|--------|-------|--------|----------------|
| 0 (CPU) | 5 t/s | ⚠️ Slow | Testing only |
| 10 | 17 t/s | ✅ Good | Conservative |
| **50** | **28 t/s** | ✅ **Best** | **Production** |
| 999 | Testing | 🔬 Experimental | Maximum offload |

---

## 🏗️ Architecture

```
┌──────────────┐
│ Remote Users │
└──────┬───────┘
       │
   Cloudflare Tunnel (optional)
       │
       ▼
┌──────────────────────┐
│ Nginx Reverse Proxy  │
│ - SSL/TLS (8443)     │
│ - Authentication     │
│ - Rate Limiting      │
└──────────┬───────────┘
           │ HTTP (8091)
           ▼
┌──────────────────────┐
│  llama-server        │
│  - Vulkan backend    │
│  - 50 GPU layers     │
│  - 16 threads        │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ AMD Radeon 780M      │
│ - gfx1103 (RDNA 3)   │
│ - RADV driver        │
│ - Unified Memory     │
└──────────────────────┘
```

---

## 🔧 System Information

### Hardware
- **CPU**: AMD Ryzen 7 8845HS (Zen 4, 8C/16T)
- **iGPU**: AMD Radeon 780M (RDNA 3, gfx1103)
- **RAM**: 64GB DDR5
- **Storage**: NVMe SSD

### Software
- **OS**: Ubuntu 24.04 LTS
- **Kernel**: 6.14.0-36-generic
- **Vulkan**: 1.3.275 (Mesa RADV driver)
- **llama.cpp**: Latest (Vulkan build)

### Model
- **Name**: Qwen3-Coder-30B-A3B-Instruct
- **Quantization**: Q4_K_M
- **Size**: 18GB
- **Context**: 262K tokens (using 8192)

---

## 📖 Essential Commands

### Service Management

```bash
# Status
systemctl status llama-server

# Control
sudo systemctl start llama-server
sudo systemctl stop llama-server
sudo systemctl restart llama-server

# Logs
journalctl -u llama-server -f
tail -f /opt/llama-server/logs/server.log
```

### Testing

```bash
# Health check
curl http://localhost:8091/health

# Simple inference
curl -s http://localhost:8091/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"test"}],"max_tokens":10}'

# Through nginx (SSL)
curl -k https://localhost:8443/health
```

### Performance Tuning

```bash
# Adjust GPU layers
sudo sed -i 's/--n-gpu-layers [0-9]\+/--n-gpu-layers 60/' \
  /etc/systemd/system/llama-server.service
sudo systemctl daemon-reload
sudo systemctl restart llama-server
```

---

## 🔗 Configuration Files

### Active Configuration (Vulkan)

| File | Path |
|------|------|
| **Service Config** | `/etc/systemd/system/llama-server.service` |
| **Binary** | `~/dev/devops/llama-server-deploy/llama.cpp/build-vulkan/bin/llama-server` |
| **Nginx Config** | `/etc/nginx/sites-available/llama-server` |
| **Server Logs** | `/opt/llama-server/logs/server.log` |
| **Error Logs** | `/opt/llama-server/logs/error.log` |

### Key Service Settings

```ini
ExecStart=~/llama-server-deploy/llama.cpp/build-vulkan/bin/llama-server \
  --model /opt/llama-server/models/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf \
  --host 127.0.0.1 \
  --port 8091 \
  --threads 16 \
  --n-gpu-layers 50 \
  --ctx-size 8192 \
  --metrics
```

---

## 🆘 Quick Troubleshooting

### Server Not Running?

```bash
systemctl status llama-server
journalctl -u llama-server -n 50
```

### Using Old ROCm Binary?

```bash
ps aux | grep llama-server
# Should show: .../build-vulkan/bin/llama-server
# NOT: .../build/bin/llama-server
```

### Poor Performance?

```bash
# Check GPU detection
journalctl -u llama-server | grep -i vulkan

# Verify Vulkan devices
vulkaninfo | grep deviceName

# Monitor GPU
watch -n 1 'rocm-smi --showmeminfo vram'
```

### 502 Gateway Errors?

```bash
# Check backend
curl http://localhost:8091/health

# Check nginx
sudo nginx -t
sudo tail -f /var/log/nginx/llama-error.log
```

**Full troubleshooting**: [LLAMA_SERVER_FIXES.md](../../../LLAMA_SERVER_FIXES.md)

---

## 📚 Extended Documentation

### For New Users
Start here → [QUICKSTART.md](../../../QUICKSTART.md)
- 5-minute setup guide
- Essential commands
- Common tasks
- Network access setup

### For Detailed Information
Read → [~/README.md](../../../README.md)
- Complete architecture overview
- API usage examples
- Performance benchmarks
- Technical deep-dive

### For Troubleshooting
Reference → [LLAMA_SERVER_FIXES.md](../../../LLAMA_SERVER_FIXES.md)
- Complete migration story
- Problem analysis
- All attempted solutions
- Lessons learned

### For Automation
Run → [setup-llama-vulkan-complete.sh](../../../setup-llama-vulkan-complete.sh)
- Automated installation
- Dependency management
- Configuration
- Testing

---

## 🎯 API Endpoints

### Base URLs
- **Direct**: `http://localhost:8091`
- **Nginx (SSL)**: `https://localhost:8443` (with auth)

### Main Endpoints
- `GET /health` - Health check (no auth)
- `POST /v1/chat/completions` - OpenAI-compatible chat
- `POST /completion` - Native completion
- `GET /metrics` - Prometheus metrics

### Example Request

```bash
curl -s http://localhost:8091/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "system", "content": "You are a helpful coding assistant."},
      {"role": "user", "content": "Write a Python hello world"}
    ],
    "temperature": 0.7,
    "max_tokens": 200
  }'
```

---

## 🔐 Network Access

### Enable LAN Access

1. **Update llama-server**:
   ```bash
   sudo sed -i 's/--host 127.0.0.1/--host 0.0.0.0/' /etc/systemd/system/llama-server.service
   sudo systemctl daemon-reload && sudo systemctl restart llama-server
   ```

2. **Update nginx**:
   ```bash
   sudo sed -i 's/listen 8443/listen 0.0.0.0:8443/' /etc/nginx/sites-available/llama-server
   sudo systemctl reload nginx
   ```

3. **Configure firewall**:
   ```bash
   sudo ufw allow 8443/tcp
   ```

4. **Get your local IP**:
   ```bash
   ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1
   ```

5. **Access from other devices**:
   ```
   https://192.168.x.x:8443/
   ```

**Detailed guide**: [QUICKSTART.md](../../../QUICKSTART.md#network-access)

---

## 📦 Repository Structure

```
llama-server-deploy/
├── README.md                       # This file
├── config.env                      # Deployment configuration
├── manage.sh                       # Management utility ✅
├── deploy.sh                       # ROCm deployment (deprecated)
├── preflight-check.sh             # System checks
├── FIXES.md                        # Early troubleshooting notes
├── deployment.log                 # Deployment history
└── llama.cpp/
    ├── build/                     # ROCm build ❌ (deprecated)
    │   └── bin/llama-server       # Old binary
    └── build-vulkan/              # Vulkan build ✅ (active)
        └── bin/llama-server       # Production binary

External Documentation (~/):
├── README.md                       # Main hub
├── QUICKSTART.md                  # Quick reference
├── LLAMA_SERVER_FIXES.md          # Complete troubleshooting
└── setup-llama-vulkan-complete.sh # Automated setup
```

---

## 🔄 Migration Summary

### What Changed (Nov 26, 2025)

**Problem**:
- ROCm/HIP backend crashed on AMD gfx1103 GPU
- Missing TensileLibrary files for gfx1103
- SIGABRT on every inference request

**Solution**:
- Built llama.cpp with Vulkan backend
- Updated service to use Vulkan binary
- Optimized GPU layers to 50

**Results**:
- ✅ Zero crashes
- ✅ Stable inference
- ✅ 28 tokens/second
- ✅ Native RADV driver support

---

## 🌐 Support & Resources

### Documentation
- **Project Docs**: All files in `~/` directory
- **Repository Docs**: This README + manage.sh

### External Resources
- **llama.cpp**: https://github.com/ggerganov/llama.cpp
- **Vulkan SDK**: https://vulkan.lunarg.com/
- **RADV Driver**: https://docs.mesa3d.org/drivers/radv.html
- **Qwen Model**: https://huggingface.co/Qwen

---

## 📜 Changelog

### v2.0.0 - Vulkan Migration (2025-11-26) ✅ CURRENT
- Migrated from ROCm to Vulkan backend
- Fixed all crash issues (SIGABRT)
- Optimized for AMD gfx1103 integrated GPU
- Achieved 28 tokens/s with 50 GPU layers
- Created comprehensive documentation suite
- Added automated setup script

### v1.0.0 - Initial ROCm Release (Deprecated)
- Initial deployment for Ubuntu 24.04
- ROCm 6.2.4 support (deprecated due to gfx1103 incompatibility)
- Nginx reverse proxy with SSL
- Multi-user authentication
- Cloudflare Tunnel integration

---

## 📄 License

This deployment configuration is provided as-is for use with:
- **llama.cpp**: MIT License
- **Vulkan**: Khronos Group
- **Individual models**: Check model-specific licenses

---

## ✅ Current Status

**Production Ready** | **Stable** | **Optimized**

- 🟢 **Service**: Running
- 🟢 **Backend**: Vulkan (RADV)
- 🟢 **Performance**: 28 tokens/s
- 🟢 **Stability**: No crashes
- 🟢 **GPU**: 50 layers offloaded

**Last Updated**: 2025-11-26
