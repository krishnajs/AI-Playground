# Proxy Configuration for Intel Network

**Issue:** npm install fails with connection timeouts when behind Intel corporate proxy.

**Root Cause:** npm not configured to use Intel's proxy servers.

---

## Quick Fix

```bash
# Configure npm to use Intel proxy
npm config set proxy http://proxy-dmz.intel.com:911
npm config set https-proxy http://proxy-dmz.intel.com:912
npm config set strict-ssl false

# Verify configuration
npm config list | grep proxy
```

---

## Environment Variables

Intel network already has these proxy variables set:

```bash
http_proxy=http://proxy-dmz.intel.com:911
https_proxy=http://proxy-dmz.intel.com:912
ftp_proxy=http://proxy-dmz.intel.com:911
socks_server=http://proxy-dmz.intel.com:1080
no_proxy=localhost,127.0.0.1,*.intel.com,...
```

npm needs to be explicitly configured to use these.

---

## Verification

Test npm connectivity:
```bash
npm ping
npm view electron versions --json | head -20
```

---

## Alternative: Use System Proxy

If npm config doesn't work, you can also try:

```bash
# Unset npm proxy config
npm config delete proxy
npm config delete https-proxy

# Install with explicit proxy environment
HTTP_PROXY=http://proxy-dmz.intel.com:911 \
HTTPS_PROXY=http://proxy-dmz.intel.com:912 \
npm install
```

---

## Electron-Specific Issue

Electron downloads binaries from GitHub releases during npm install. Behind corporate proxy, this can fail. Solutions:

1. **Use npm proxy settings** (preferred)
2. **Use Electron mirror:**
   ```bash
   ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/" npm install
   ```
3. **Manual download:** Download Electron from internal mirror and cache it

---

## Troubleshooting

If still failing:

```bash
# Check if proxy is reachable
curl -x http://proxy-dmz.intel.com:911 https://registry.npmjs.org/

# Check npm debug logs
npm install --verbose 2>&1 | grep -i proxy

# Clear npm cache
npm cache clean --force
```

---

## One-Time Setup Script

Save this as `setup-npm-proxy.sh`:

```bash
#!/bin/bash
# Configure npm for Intel corporate network

echo "Configuring npm proxy settings..."
npm config set proxy http://proxy-dmz.intel.com:911
npm config set https-proxy http://proxy-dmz.intel.com:912
npm config set strict-ssl false

echo "Proxy configuration complete!"
npm config list | grep proxy
```

Make executable: `chmod +x setup-npm-proxy.sh`

---

**Last Updated:** April 20, 2026
