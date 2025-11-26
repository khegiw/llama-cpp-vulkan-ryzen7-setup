# Quick Start Guide

Get your llama.cpp ROCm server running in 4 steps.

## Prerequisites

- Ubuntu 24.04.3 LTS
- AMD Ryzen 7 8845HS with Radeon 780M Graphics
- At least 16GB RAM
- 50GB+ free disk space
- Internet connection

## Step 1: Pre-flight Check (2 minutes)

```bash
cd llama-server-deploy
./preflight-check.sh
```

✅ All checks should pass or show warnings only (not failures).

## Step 2: Configure (5 minutes)

Edit `config.env`:

```bash
nano config.env
```

**Essential settings:**

```bash
# Model to download (choose one)
MODEL_NAME="qwen2.5-coder-7b-instruct-q5_k_m.gguf"
MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q5_k_m.gguf"

# Users (you'll set passwords during deployment)
USERS=("user1" "user2" "user3")

# Remote access (set to true if you want Cloudflare Tunnel)
SETUP_CLOUDFLARE=false  # Change to true for remote access
```

Save and exit (Ctrl+X, Y, Enter).

## Step 3: Deploy (30-60 minutes)

```bash
./deploy.sh
```

The script will:
- ✅ Install ROCm (~10 min)
- ✅ Build llama.cpp (~5 min)
- ✅ Download model (~10-20 min depending on connection)
- ✅ Setup services (~5 min)
- ✅ Configure nginx and SSL (~2 min)

**You'll be prompted for:**
- Confirmation to proceed
- Passwords for each user (during nginx setup)
- Cloudflare authentication (if enabled)

## Step 4: Reboot & Test (5 minutes)

```bash
# Reboot for ROCm
sudo reboot
```

**After reboot:**

```bash
cd llama-server-deploy

# Verify ROCm
rocminfo | grep gfx
# Should show: gfx1103

# Check status
./manage.sh status
# Should show: ✓ Running

# Test the server
./manage.sh test
# Should show: ✓ Health check passed
```

## Usage Examples

### Health Check
```bash
curl -k https://localhost:8443/health
```

### Code Completion
```bash
curl -k -u user1:password https://localhost:8443/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Write a Python function to calculate fibonacci",
    "n_predict": 200
  }'
```

### Chat Interface (OpenAI-compatible)
```bash
curl -k -u user1:password https://localhost:8443/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "system", "content": "You are a coding assistant."},
      {"role": "user", "content": "How do I read a CSV file in Python?"}
    ],
    "max_tokens": 500
  }'
```

## Management Commands

```bash
# Show status
./manage.sh status

# View logs
./manage.sh logs llama-server

# Restart server
./manage.sh restart

# Monitor GPU
./manage.sh gpu

# Manage users
./manage.sh users

# Run diagnostics
./manage.sh diagnostics
```

## Common Issues

### "ROCm not detecting GPU"
```bash
# Check groups
groups
# Should include: render, video

# If missing, add yourself
sudo usermod -a -G render,video $USER
# Then logout and login again
```

### "Service fails to start"
```bash
# Check logs
./manage.sh logs llama-server

# Verify model exists
ls -lh /opt/llama-server/models/

# Check environment
./manage.sh diagnostics
```

### "Authentication failed"
```bash
# Reset password
./manage.sh users
# Choose option 3 to change password
```

## Next Steps

- 📖 Read full [README.md](README.md) for advanced configuration
- 🔧 Tune performance in `/etc/systemd/system/llama-server.service`
- 🌐 Setup Cloudflare Tunnel for remote access
- 📊 Add monitoring (Prometheus + Grafana)
- 🔄 Try different models from [Hugging Face](https://huggingface.co/models?library=gguf)

## Quick Reference

| File | Purpose |
|------|---------|
| `config.env` | Configuration settings |
| `deploy.sh` | Main deployment script |
| `manage.sh` | Server management utility |
| `preflight-check.sh` | System requirements checker |
| `README.md` | Full documentation |

## Support

If you encounter issues:

1. Check `deployment.log` for errors
2. Run `./manage.sh diagnostics`
3. Review full docs in `README.md`
4. Check llama.cpp issues: https://github.com/ggerganov/llama.cpp/issues

---

**Total setup time: ~45-75 minutes** (mostly automated)

**Ready to code with AI! 🚀**
