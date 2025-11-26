# llama.cpp ROCm Server Deployment

Automated deployment solution for running llama.cpp with AMD ROCm GPU acceleration on Ubuntu 24.04.

## Overview

This deployment provides a production-ready LLM inference server optimized for:
- **Hardware**: AMD Ryzen 7 8845HS with Radeon 780M Graphics
- **GPU**: RDNA 3 architecture (gfx1103)
- **Use Case**: Code assistance with models like Qwen-Coder
- **Users**: 3 concurrent users (1 local, 2 remote)

## Architecture

```
Remote Users → Cloudflare Tunnel → Nginx (SSL/Auth) → llama-server → ROCm → GPU
Local User  → Nginx (SSL/Auth) → llama-server → ROCm → GPU
```

### Components

- **llama.cpp**: GPU-accelerated LLM inference engine
- **ROCm 6.2.4**: AMD GPU compute platform
- **Nginx**: Reverse proxy with SSL/TLS and authentication
- **Systemd**: Service management with auto-restart
- **Cloudflare Tunnel**: Secure remote access (optional)

### Security Features

✅ Basic authentication (user accounts)
✅ SSL/TLS encryption
✅ Rate limiting (10 req/s, burst 20)
✅ Local-only server binding
✅ Cloudflare WAF protection (optional)
✅ Service isolation and resource limits

## Quick Start

### 1. Pre-flight Check

Verify your system meets requirements:

```bash
cd llama-server-deploy
chmod +x *.sh
./preflight-check.sh
```

Expected output: System checks with pass/warn/fail indicators.

### 2. Configure Deployment

Edit `config.env` to customize your setup:

```bash
nano config.env
```

Key settings to review:
- `MODEL_NAME` and `MODEL_URL` - Which model to download
- `USERS` - Array of usernames for authentication
- `SETUP_CLOUDFLARE` - Enable remote access (true/false)
- `GPU_LAYERS` - GPU offloading (-1 for auto, 33 for full)

### 3. Run Deployment

Execute the automated deployment:

```bash
./deploy.sh
```

The script will:
1. Install ROCm 6.2.4
2. Build llama.cpp with GPU support
3. Download your chosen model
4. Setup systemd service
5. Configure nginx with SSL
6. Setup Cloudflare Tunnel (if enabled)

**Important**: Reboot after deployment for ROCm changes to take effect.

### 4. Verify Installation

After reboot:

```bash
# Check ROCm GPU detection
rocminfo | grep gfx
# Should show: gfx1103

# Check service status
./manage.sh status

# Run health test
./manage.sh test
```

## Management

The `manage.sh` utility provides comprehensive server management:

### Common Commands

```bash
# Show server status
./manage.sh status

# View logs
./manage.sh logs llama-server
./manage.sh logs nginx

# Follow logs in real-time
./manage.sh follow llama-server

# Restart services
./manage.sh restart

# Monitor GPU
./manage.sh gpu

# Run tests
./manage.sh test

# User management
./manage.sh users

# System diagnostics
./manage.sh diagnostics

# Create backup
./manage.sh backup
```

### Service Control

```bash
# Start/stop individual services
sudo systemctl start llama-server
sudo systemctl stop llama-server
sudo systemctl restart llama-server
sudo systemctl status llama-server

# View service logs
sudo journalctl -u llama-server -f
```

## Usage Examples

### Local Testing

```bash
# Health check (no auth required)
curl -k https://localhost:8443/health

# Authenticated completion request
curl -k -u user1:password https://localhost:8443/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Write a Python function to calculate fibonacci numbers",
    "n_predict": 200,
    "temperature": 0.7
  }'
```

### Chat Completion (OpenAI-compatible API)

```bash
curl -k -u user1:password https://localhost:8443/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "system", "content": "You are a helpful coding assistant."},
      {"role": "user", "content": "How do I read a file in Python?"}
    ],
    "temperature": 0.7,
    "max_tokens": 500
  }'
```

### Streaming Response

```bash
curl -k -u user1:password https://localhost:8443/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain async/await in JavaScript",
    "stream": true,
    "n_predict": 300
  }' \
  --no-buffer
```

### Python Client Example

```python
import requests
from requests.auth import HTTPBasicAuth

url = "https://localhost:8443/completion"
auth = HTTPBasicAuth("user1", "password")

payload = {
    "prompt": "Write a function to reverse a string",
    "n_predict": 200,
    "temperature": 0.7,
    "stop": ["\n\n"]
}

response = requests.post(
    url,
    json=payload,
    auth=auth,
    verify=False  # Self-signed cert
)

print(response.json()["content"])
```

## Configuration

### Model Selection

Recommended models for Radeon 780M (shared 16GB RAM):

| Model | Size | Quantization | Use Case | Performance |
|-------|------|--------------|----------|-------------|
| Qwen2.5-Coder-7B | 7B | Q5_K_M | Balanced | ~20 tok/s |
| Qwen2.5-Coder-7B | 7B | Q4_K_M | Faster | ~25 tok/s |
| Qwen2.5-Coder-14B | 14B | Q4_K_M | Better quality | ~12 tok/s |
| Qwen2.5-Coder-1.5B | 1.5B | Q5_K_M | Ultra fast | ~40 tok/s |

To switch models:

1. Download new model to `${INSTALL_DIR}/models/`
2. Update `MODEL_NAME` in `config.env`
3. Update systemd service or restart with new model

```bash
# Quick model switch
./manage.sh model
```

### Performance Tuning

Edit `/etc/systemd/system/llama-server.service`:

```ini
# More GPU layers (max quality, slower CPU)
--n-gpu-layers 33

# Fewer GPU layers (balanced)
--n-gpu-layers 25

# Context size (memory vs performance)
--ctx-size 8192    # Default
--ctx-size 16384   # Larger context
--ctx-size 4096    # Lower memory

# Parallel requests (users vs performance)
--parallel 3       # 3 users
--parallel 1       # Single user, best performance
```

After changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart llama-server
```

### Rate Limiting

Edit `/etc/nginx/sites-available/llama-server`:

```nginx
# Requests per second
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

# Burst allowance
limit_req zone=api_limit burst=20 nodelay;

# Connection limit
limit_conn conn_limit 10;
```

After changes:
```bash
sudo nginx -t
sudo systemctl restart nginx
```

## Cloudflare Tunnel Setup

If you enabled `SETUP_CLOUDFLARE=true`:

### Initial Setup

1. Domain must be added to Cloudflare
2. Run deployment, it will prompt for authentication
3. Provide desired hostname (e.g., `llama.yourdomain.com`)

### Access Policies

Add Zero Trust rules in Cloudflare dashboard:

1. Go to Zero Trust → Access → Applications
2. Create new application for your tunnel hostname
3. Add policies (IP restrictions, email domain, etc.)

### Management

```bash
# Check tunnel status
sudo systemctl status cloudflared

# View tunnel logs
./manage.sh logs cloudflared

# List tunnels
cloudflared tunnel list

# Delete tunnel
cloudflared tunnel delete llama-server
```

## Monitoring

### Real-time Monitoring

```bash
# Watch GPU usage
./manage.sh gpu

# Or directly with radeontop
radeontop

# ROCm stats
watch -n 1 rocm-smi

# System resources
htop
```

### Log Locations

- Server logs: `/opt/llama-server/logs/server.log`
- Error logs: `/opt/llama-server/logs/error.log`
- Nginx access: `/var/log/nginx/llama-access.log`
- Nginx errors: `/var/log/nginx/llama-error.log`
- Systemd journal: `journalctl -u llama-server`

### Performance Metrics

Access Prometheus-compatible metrics:

```bash
curl -u user1:password https://localhost:8443/metrics
```

## Troubleshooting

### Server Won't Start

```bash
# Check detailed status
sudo systemctl status llama-server

# View recent logs
./manage.sh logs llama-server 100

# Check ROCm detection
rocminfo | grep gfx

# Verify model file exists
ls -lh /opt/llama-server/models/
```

### GPU Not Detected

```bash
# Run diagnostics
./manage.sh diagnostics

# Check user groups
groups
# Should include: render, video

# Re-add to groups if missing
sudo usermod -a -G render,video $USER
# Then logout and login again

# Verify environment
echo $HSA_OVERRIDE_GFX_VERSION
# Should be: 11.0.3
```

### Poor Performance

```bash
# Run benchmark
./manage.sh benchmark

# Check GPU offloading
./manage.sh logs llama-server | grep "gpu"

# Monitor during request
./manage.sh gpu
# In another terminal, make a request
```

### Authentication Issues

```bash
# List users
./manage.sh users

# Reset password
sudo htpasswd /etc/nginx/.htpasswd username

# Check nginx config
sudo nginx -t
./manage.sh logs nginx
```

### Connection Refused

```bash
# Check if services are running
./manage.sh status

# Check ports
sudo ss -tulpn | grep -E ":(8080|8443)"

# Check firewall
sudo ufw status

# Test direct connection
curl http://127.0.0.1:8080/health
```

## Advanced Configuration

### Custom SSL Certificate

Replace self-signed cert with your own:

```bash
# Copy your certificate
sudo cp your-cert.crt /etc/nginx/ssl/llama-server.crt
sudo cp your-key.key /etc/nginx/ssl/llama-server.key

# Set permissions
sudo chmod 600 /etc/nginx/ssl/llama-server.key
sudo chmod 644 /etc/nginx/ssl/llama-server.crt

# Restart nginx
sudo systemctl restart nginx
```

### Adding More Users

```bash
# Use management script
./manage.sh users

# Or manually
sudo htpasswd /etc/nginx/.htpasswd newuser
```

### Resource Limits

Edit `/etc/systemd/system/llama-server.service`:

```ini
# Memory limit
MemoryMax=24G

# CPU quota (800% = 8 cores)
CPUQuota=800%

# Maximum open files
LimitNOFILE=65536
```

### Multiple Models

Run multiple instances on different ports:

1. Copy and modify service file
2. Change `--port` and `--model`
3. Add new nginx upstream and location
4. Start additional service

## Backup and Recovery

### Create Backup

```bash
# Automated backup
./manage.sh backup

# Manual backup
tar -czf backup.tar.gz \
  /opt/llama-server/models/ \
  /etc/systemd/system/llama-server.service \
  /etc/nginx/sites-available/llama-server \
  /etc/nginx/.htpasswd
```

### Restore from Backup

```bash
# Extract backup
tar -xzf backup.tar.gz

# Copy files to original locations
sudo cp -r backup/opt/llama-server/models/* /opt/llama-server/models/
sudo cp backup/etc/systemd/system/llama-server.service /etc/systemd/system/
sudo cp backup/etc/nginx/sites-available/llama-server /etc/nginx/sites-available/

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart llama-server nginx
```

## Upgrading

### Update llama.cpp

```bash
cd llama-server-deploy/llama.cpp
git pull
cmake --build build --config Release -j$(nproc)
sudo cp build/bin/llama-server /usr/local/bin/
sudo systemctl restart llama-server
```

### Update ROCm

```bash
sudo apt update
sudo apt upgrade rocm-hip-sdk rocm-dev rocm-libs
sudo reboot
```

### Update Model

```bash
# Download new model
wget -P /opt/llama-server/models/ https://huggingface.co/...

# Update config
nano config.env
# Change MODEL_NAME

# Restart service
sudo systemctl restart llama-server
```

## Uninstall

```bash
# Stop and disable services
sudo systemctl stop llama-server nginx cloudflared
sudo systemctl disable llama-server cloudflared

# Remove service files
sudo rm /etc/systemd/system/llama-server.service
sudo systemctl daemon-reload

# Remove nginx config
sudo rm /etc/nginx/sites-enabled/llama-server
sudo rm /etc/nginx/sites-available/llama-server

# Remove installation directory
sudo rm -rf /opt/llama-server

# Optionally remove ROCm
sudo apt remove --purge rocm-hip-sdk rocm-dev rocm-libs
```

## Performance Benchmarks

Expected performance on Ryzen 7 8845HS + Radeon 780M:

| Configuration | Prompt Processing | Generation | Power |
|---------------|-------------------|------------|-------|
| 7B Q5_K_M, 33 layers | ~20 tok/s | ~6-8 tok/s | 25-30W |
| 7B Q4_K_M, 33 layers | ~25 tok/s | ~8-10 tok/s | 28-32W |
| 14B Q4_K_M, 25 layers | ~12 tok/s | ~4-5 tok/s | 30-35W |

## API Documentation

Full API documentation available at:
- OpenAI-compatible: `https://localhost:8443/v1/chat/completions`
- Native API: `https://localhost:8443/completion`
- API docs: `https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md`

## Support and Resources

- **llama.cpp**: https://github.com/ggerganov/llama.cpp
- **ROCm Documentation**: https://rocm.docs.amd.com/
- **Issue Tracker**: Check deployment.log for errors

## License

This deployment configuration is provided as-is for use with:
- llama.cpp (MIT License)
- ROCm (Various open source licenses)
- Individual models (check model-specific licenses)

## Changelog

### v1.0.0 - Initial Release
- Automated deployment for Ubuntu 24.04
- ROCm 6.2.4 support
- Radeon 780M optimization (gfx1103)
- Nginx reverse proxy with SSL
- Multi-user authentication
- Cloudflare Tunnel integration
- Comprehensive management utilities

---

**Deployed with DevOps best practices by Alex, DevOps Infrastructure Specialist**
