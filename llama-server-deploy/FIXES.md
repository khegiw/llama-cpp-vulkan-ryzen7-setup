# Deployment Fixes Applied

This document summarizes the fixes applied to resolve deployment issues with the llama.cpp ROCm server.

## Issue Summary

The initial deployment encountered several configuration issues that prevented the llama-server service from starting correctly.

---

## Fix #1: Invalid Model Filename

### Problem
```bash
/opt/llama-server/models/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF: No such file or directory
```

### Root Cause
The `MODEL_NAME` in `config.env` was set to `"unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF"`, which included the repository path with a slash. The deployment script tried to create a nested directory structure that didn't exist.

### Solution
Changed `MODEL_NAME` in `config.env` from:
```bash
MODEL_NAME="unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF"
```

To:
```bash
MODEL_NAME="Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"
```

### Files Modified
- `config.env` (line 21)

---

## Fix #2: Incorrect Model URL

### Problem
The original URL pointed to a non-existent model file:
```
https://huggingface.co/.../qwen3-coder-30b-a3b-instruct.gguf
```

### Root Cause
The model repository doesn't have a file with the generic name. All files have specific quantization suffixes (Q4_K_M, Q8_0, etc.).

### Solution
Updated `MODEL_URL` in `config.env` to point to the recommended Q4_K_M quantization:
```bash
MODEL_URL="https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"
```

### Why Q4_K_M?
- Best balance between quality and size
- Widely recommended for production use
- Smaller file size than Q8_0 while maintaining good quality
- Faster inference than higher quantizations

### Files Modified
- `config.env` (line 22)

---

## Fix #3: Unsupported Command-Line Argument

### Problem
```bash
error: invalid argument: --log-format
```

The service failed to start with exit code 1.

### Root Cause
The systemd service file included `--log-format text` parameter, which is not supported by this version of llama-server.

### Solution
Removed the `--log-format text` line from the ExecStart command in both:
1. The systemd service template in `deploy.sh`
2. The active service file at `/etc/systemd/system/llama-server.service`

**Before:**
```bash
ExecStart=/usr/local/bin/llama-server \
  --model /opt/llama-server/models/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf \
  --host 127.0.0.1 \
  --port 8091 \
  --threads 16 \
  --n-gpu-layers 33 \
  --ctx-size 8192 \
  --parallel 3 \
  --metrics \
  --log-format text    # ← REMOVED
```

**After:**
```bash
ExecStart=/usr/local/bin/llama-server \
  --model /opt/llama-server/models/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf \
  --host 127.0.0.1 \
  --port 8091 \
  --threads 16 \
  --n-gpu-layers 33 \
  --ctx-size 8192 \
  --parallel 3 \
  --metrics
```

### Files Modified
- `deploy.sh` (line 327-328)
- `/etc/systemd/system/llama-server.service` (when service is recreated)

---

## Fix #4: Smart Service Detection

### Enhancement
Added intelligent service state detection to avoid unnecessary reconfigurations.

### Implementation
The `setup_server_service()` function now:
1. Checks if llama-server service is already running
2. Prompts user whether to reconfigure
3. Skips setup if service is working correctly
4. Only stops and reconfigures if user confirms

### Code Added (deploy.sh lines 295-306)
```bash
# Check if service is already running
if systemctl is-active --quiet llama-server 2>/dev/null; then
    log_info "llama-server service is already running"
    read -p "Reconfigure and restart service? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping service setup (already running)"
        return
    fi
    log_info "Stopping service for reconfiguration..."
    sudo systemctl stop llama-server
fi
```

### Benefits
- Prevents accidental service disruption
- Speeds up re-runs of the deployment script
- Allows incremental fixes without full redeployment

---

## Fix #5: Smart User Management for Nginx

### Enhancement
Added intelligent user account management for nginx authentication to prevent duplicate users and allow password updates.

### Implementation
The `setup_nginx()` function now:
1. Checks if each user already exists in `/etc/nginx/.htpasswd`
2. For existing users, prompts with options:
   - **(c)hange password**: Update password for existing user
   - **(s)kip**: Keep existing user unchanged
   - **(d)elete and recreate**: Remove and recreate user with new password
3. For new users, creates them normally
4. Handles .htpasswd file creation properly (uses -c flag only for first user when file doesn't exist)

### Code Added (deploy.sh lines 413-462)
```bash
# Check if .htpasswd exists
htpasswd_exists=false
if [ -f /etc/nginx/.htpasswd ]; then
    htpasswd_exists=true
fi

for i in "${!USERS[@]}"; do
    username="${USERS[$i]}"

    # Check if user already exists
    user_exists=false
    if [ "$htpasswd_exists" = true ] && sudo grep -q "^${username}:" /etc/nginx/.htpasswd 2>/dev/null; then
        user_exists=true
    fi

    if [ "$user_exists" = true ]; then
        log_info "User '${username}' already exists"
        echo "Options: (c)hange password, (s)kip, (d)elete and recreate"
        read -p "Action for ${username}? (c/s/d): " -n 1 -r
        echo

        case $REPLY in
            [Cc])
                log_info "Changing password for user: ${username}"
                sudo htpasswd /etc/nginx/.htpasswd "$username"
                ;;
            [Ss])
                log_info "Skipping user: ${username}"
                ;;
            [Dd])
                log_info "Deleting and recreating user: ${username}"
                sudo htpasswd -D /etc/nginx/.htpasswd "$username" 2>/dev/null || true
                sudo htpasswd /etc/nginx/.htpasswd "$username"
                ;;
            *)
                log_warning "Invalid option, skipping user: ${username}"
                ;;
        esac
    else
        # Create new user
        ...
    fi
done
```

### Benefits
- Prevents duplicate user errors
- Allows password updates without manual file editing
- Provides flexibility to skip users that are already configured
- Safer re-runs of deployment script without losing existing credentials
- Clear user feedback on existing accounts

---

## Verification Steps

### 1. Verify Model File Exists
```bash
ls -lh /opt/llama-server/models/
# Should show: Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf
```

### 2. Verify Service Configuration
```bash
systemctl cat llama-server.service | grep -A 10 "ExecStart"
# Should NOT contain --log-format
```

### 3. Verify Service is Running
```bash
sudo systemctl status llama-server
# Should show: Active: active (running)
```

### 4. Test ROCm GPU Detection
```bash
journalctl -u llama-server -n 50 | grep -i "rocm\|gpu\|gfx"
# Should show: found 1 ROCm devices: AMD Radeon Graphics, gfx1103
```

### 5. Test Health Endpoint
```bash
curl -s http://127.0.0.1:8091/health
# Should return: {"status":"ok"}
```

### 6. Test Completion Endpoint
```bash
curl http://127.0.0.1:8091/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Write a hello world in Python",
    "n_predict": 50
  }'
```

### 7. Verify GPU Utilization (during inference)
```bash
rocm-smi
# Should show GPU activity when processing requests
```

---

## Quick Recovery Commands

If the service fails after applying fixes:

```bash
# Stop the service
sudo systemctl stop llama-server

# Apply the corrected service file
sudo cp /tmp/llama-server.service /etc/systemd/system/llama-server.service

# Reload systemd
sudo systemctl daemon-reload

# Restart the service
sudo systemctl restart llama-server

# Check status
sudo systemctl status llama-server

# View detailed logs
journalctl -u llama-server -f
```

---

## Files Modified Summary

| File | Lines Modified | Change Description |
|------|----------------|-------------------|
| `config.env` | 21 | Fixed MODEL_NAME to use filename only |
| `config.env` | 22 | Updated MODEL_URL to Q4_K_M variant |
| `deploy.sh` | 8-12 | Added fix summary in header comments |
| `deploy.sh` | 295-306 | Added service running check |
| `deploy.sh` | 327 | Removed --log-format parameter |
| `deploy.sh` | 413-462 | Added smart user management for nginx |

---

## Additional Notes

### Model Quantization Choices

If you want to use a different quantization, available options are:

- **Q2_K**: ~11GB, fastest, lowest quality
- **Q3_K_M**: ~13GB, good for limited RAM
- **Q4_K_M**: ~16GB, **recommended** (current)
- **Q5_K_M**: ~19GB, better quality
- **Q6_K**: ~22GB, high quality
- **Q8_0**: ~29GB, highest quality

Update both `MODEL_NAME` and `MODEL_URL` in `config.env` if changing quantization.

### Troubleshooting

If issues persist:

1. Check logs: `sudo journalctl -u llama-server -n 100`
2. Test manually: `/usr/local/bin/llama-server --help`
3. Verify ROCm: `rocminfo | grep gfx`
4. Check GPU access: `ls -la /dev/kfd /dev/dri/render*`

---

## Date Applied
2025-11-25

## Applied By
Claude Code Assistant
