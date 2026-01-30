# SWE-bench configuration for running AI coding benchmarks
# 
# This module sets up mini-swe-agent for running SWE-bench evaluations
# using your local vLLM instance with Qwen2.5-Coder-7B.
#
# Usage:
#   1. Rebuild: sudo nixos-rebuild switch --flake .#nixos
#   2. Run 'swe-bench-setup' to install mini-swe-agent
#   3. Wait for vLLM to load the model (first run downloads ~28GB)
#   4. Run 'swe-bench-test' to verify setup
#   5. Run 'mini-agent' for interactive use or 'swe-bench-run' to benchmark
#
# mini-swe-agent is a 100-line Python agent that scores >74% on SWE-bench Verified
# with top models. It's simpler than full SWE-agent and works great with local models.
# https://github.com/SWE-agent/mini-swe-agent
#
{ config, lib, pkgs, ... }:

let
  # Library path for pip-installed packages with C extensions (numpy, etc.)
  libPath = lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];

  # mini-swe-agent runner script for interactive use
  mini-agent = pkgs.writeShellScriptBin "mini-agent" ''
    set -e
    
    VENV_DIR="$HOME/.swe-agent-venv"
    
    # Set library path for numpy and other C extensions
    export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"
    
    # Configure for local vLLM
    export OPENAI_API_KEY="''${OPENAI_API_KEY:-not-needed}"
    export OPENAI_BASE_URL="''${OPENAI_BASE_URL:-http://localhost:8000/v1}"
    # Ignore cost tracking errors for local models not in LiteLLM's price DB
    export MSWEA_COST_TRACKING="ignore_errors"
    # Use openai/ prefix for litellm compatibility
    MODEL_NAME="''${MODEL_NAME:-openai/Qwen/Qwen2.5-Coder-7B-Instruct}"
    
    # Activate virtual environment
    if [ ! -d "$VENV_DIR" ]; then
      echo "mini-swe-agent not installed. Run 'swe-bench-setup' first."
      exit 1
    fi
    source "$VENV_DIR/bin/activate"
    
    # Check if mini-swe-agent is installed
    if ! command -v mini &> /dev/null; then
      echo "mini-swe-agent not found in venv. Run 'swe-bench-setup' first."
      exit 1
    fi
    
    # Check if vLLM is running
    if ! curl -s "$OPENAI_BASE_URL/models" > /dev/null 2>&1; then
      echo "Warning: vLLM not responding at $OPENAI_BASE_URL"
      echo "Start it with: systemctl start podman-vllm"
      echo ""
    fi
    
    # Run mini-swe-agent with visual UI
    # If a task is provided as argument, pass it with --task
    if [ $# -gt 0 ]; then
      exec mini -v --model "$MODEL_NAME" --task "$*"
    else
      exec mini -v --model "$MODEL_NAME"
    fi
  '';

  # SWE-bench benchmark runner
  swe-bench-run = pkgs.writeShellScriptBin "swe-bench-run" ''
    set -e
    
    VENV_DIR="$HOME/.swe-agent-venv"
    
    # Set library path for numpy and other C extensions
    export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"
    
    # Configure for local vLLM
    export OPENAI_API_KEY="''${OPENAI_API_KEY:-not-needed}"
    export OPENAI_BASE_URL="''${OPENAI_BASE_URL:-http://localhost:8000/v1}"
    # Ignore cost tracking errors for local models not in LiteLLM's price DB
    export MSWEA_COST_TRACKING="ignore_errors"
    # Use openai/ prefix for litellm compatibility
    MODEL_NAME="''${MODEL_NAME:-openai/Qwen/Qwen2.5-Coder-7B-Instruct}"
    DATASET="''${DATASET:-princeton-nlp/SWE-bench_Lite}"
    
    # Activate virtual environment
    if [ ! -d "$VENV_DIR" ]; then
      echo "mini-swe-agent not installed. Run 'swe-bench-setup' first."
      exit 1
    fi
    source "$VENV_DIR/bin/activate"
    
    echo "=== SWE-bench Runner (mini-swe-agent) ==="
    echo "vLLM URL: $OPENAI_BASE_URL"
    echo "Model: $MODEL_NAME"
    echo "Dataset: $DATASET"
    echo ""
    
    # Check if mini-swe-agent is installed
    if ! command -v mini &> /dev/null; then
      echo "mini-swe-agent not found. Run 'swe-bench-setup' first."
      exit 1
    fi
    
    # Check if vLLM is running
    if ! curl -s "$OPENAI_BASE_URL/models" > /dev/null 2>&1; then
      echo "Error: vLLM is not running at $OPENAI_BASE_URL"
      echo "Start it with: systemctl start podman-vllm"
      exit 1
    fi
    
    echo "vLLM is running. Available models:"
    curl -s "$OPENAI_BASE_URL/models" | ${pkgs.jq}/bin/jq -r '.data[].id'
    echo ""
    
    # Run SWE-bench evaluation using mini-extra swebench command
    # --subset: lite (300), verified (500), or full (2294)
    # --slice: range like 0:1 for first instance
    echo "Starting SWE-bench evaluation..."
    exec mini-extra swebench \
      --model "$MODEL_NAME" \
      --subset lite \
      --output "$HOME/.mini-swe-agent/runs" \
      "$@"
  '';

  # Quick test script to verify setup
  swe-bench-test = pkgs.writeShellScriptBin "swe-bench-test" ''
    set -e
    
    VENV_DIR="$HOME/.swe-agent-venv"
    
    # Set library path for numpy and other C extensions
    export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"
    
    # Configure for local vLLM
    export OPENAI_API_KEY="''${OPENAI_API_KEY:-not-needed}"
    export OPENAI_BASE_URL="''${OPENAI_BASE_URL:-http://localhost:8000/v1}"
    MODEL_NAME="''${MODEL_NAME:-Qwen/Qwen2.5-Coder-7B-Instruct}"
    
    echo "=== SWE-bench Setup Test ==="
    echo ""
    
    # Test 1: Check Docker/Podman
    echo "[1/5] Checking container runtime..."
    if podman info > /dev/null 2>&1; then
      echo "  ✓ Podman is running"
    elif docker info > /dev/null 2>&1; then
      echo "  ✓ Docker is running"
    else
      echo "  ✗ No container runtime available"
      exit 1
    fi
    
    # Test 2: Check NVIDIA GPU
    echo "[2/5] Checking NVIDIA GPU..."
    if nvidia-smi > /dev/null 2>&1; then
      GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
      GPU_MEM=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | head -1)
      echo "  ✓ GPU: $GPU_NAME ($GPU_MEM)"
    else
      echo "  ✗ NVIDIA GPU not available"
      exit 1
    fi
    
    # Test 3: Check vLLM
    echo "[3/5] Checking vLLM..."
    if curl -s "$OPENAI_BASE_URL/models" > /dev/null 2>&1; then
      MODEL=$(curl -s "$OPENAI_BASE_URL/models" | ${pkgs.jq}/bin/jq -r '.data[0].id // "none"')
      echo "  ✓ vLLM running with model: $MODEL"
    else
      echo "  ✗ vLLM not responding at $OPENAI_BASE_URL"
      echo "    Check with: journalctl -u podman-vllm -f"
      exit 1
    fi
    
    # Test 4: Quick inference test
    echo "[4/5] Testing inference..."
    RESPONSE=$(curl -s "$OPENAI_BASE_URL/chat/completions" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in exactly 3 words\"}],
        \"max_tokens\": 20
      }" | ${pkgs.jq}/bin/jq -r '.choices[0].message.content // "error"')
    
    if [ "$RESPONSE" != "error" ] && [ -n "$RESPONSE" ]; then
      echo "  ✓ Inference working: \"$RESPONSE\""
    else
      echo "  ✗ Inference failed"
      exit 1
    fi
    
    # Test 5: Check mini-swe-agent
    echo "[5/5] Checking mini-swe-agent..."
    if [ -d "$VENV_DIR" ]; then
      source "$VENV_DIR/bin/activate"
      if command -v mini &> /dev/null; then
        VERSION=$(mini --version 2>/dev/null || echo "installed")
        echo "  ✓ mini-swe-agent: $VERSION"
      else
        echo "  ⚠ mini-swe-agent venv exists but 'mini' not found"
        echo "    Run 'swe-bench-setup' to reinstall"
      fi
    else
      echo "  ⚠ mini-swe-agent not installed yet"
      echo "    Run 'swe-bench-setup' to install it"
    fi
    
    echo ""
    echo "=== All checks passed! ==="
    echo ""
    echo "Commands available:"
    echo "  mini-agent         - Interactive agent with visual UI"
    echo "  swe-bench-run      - Run SWE-bench evaluation"
    echo "  swe-bench-status   - View latest run results"
    echo ""
    echo "Quick start:"
    echo "  mini-agent 'Write a hello world script'"
  '';

  # Setup script to install mini-swe-agent in a venv
  swe-bench-setup = pkgs.writeShellScriptBin "swe-bench-setup" ''
    set -e
    
    VENV_DIR="$HOME/.swe-agent-venv"
    
    # Set library path for numpy and other C extensions
    export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"
    
    echo "=== SWE-bench Setup (mini-swe-agent) ==="
    echo ""
    
    echo "[1/3] Creating Python virtual environment..."
    if [ -d "$VENV_DIR" ]; then
      echo "  Removing existing venv..."
      rm -rf "$VENV_DIR"
    fi
    ${pkgs.python312}/bin/python -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    
    echo "[2/4] Installing mini-swe-agent and dependencies..."
    pip install --upgrade pip
    pip install mini-swe-agent datasets
    
    # Verify installation
    if command -v mini &> /dev/null; then
      VERSION=$(mini --version 2>/dev/null || echo "installed")
      echo "  ✓ mini-swe-agent installed: $VERSION"
    else
      echo "  ✗ Installation failed"
      exit 1
    fi
    
    echo ""
    echo "[3/4] Configuring mini-swe-agent for local vLLM..."
    CONFIG_DIR="$HOME/.config/mini-swe-agent"
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/.env" << 'ENVEOF'
# mini-swe-agent configuration for local vLLM
# Model uses openai/ prefix for litellm compatibility
DEFAULT_MODEL=openai/Qwen/Qwen2.5-Coder-7B-Instruct
OPENAI_API_KEY=not-needed
OPENAI_BASE_URL=http://localhost:8000/v1
# Ignore cost tracking errors for local models not in LiteLLM's price DB
MSWEA_COST_TRACKING=ignore_errors
ENVEOF
    echo "  ✓ Config written to $CONFIG_DIR/.env"
    
    echo ""
    echo "[4/4] Checking vLLM..."
    if curl -s "http://localhost:8000/v1/models" > /dev/null 2>&1; then
      echo "  ✓ vLLM is running"
    else
      echo "  ⚠ vLLM not responding yet"
      echo "    Check with: journalctl -u podman-vllm -f"
    fi
    
    echo ""
    echo "=== Setup complete! ==="
    echo ""
    echo "Virtual environment: $VENV_DIR"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'swe-bench-test' to verify everything works"
    echo "  2. Run 'mini-agent' for interactive use"
    echo "  3. Run 'swe-bench-run' to benchmark"
  '';

  # Status script to view results
  swe-bench-status = pkgs.writeShellScriptBin "swe-bench-status" ''
    set -e
    
    RESULTS_DIR="$HOME/.mini-swe-agent"
    
    echo "=== SWE-bench Results ==="
    echo ""
    
    if [ ! -d "$RESULTS_DIR" ]; then
      echo "No results found yet."
      echo "Run 'swe-bench-run' to start benchmarking."
      exit 0
    fi
    
    echo "Results directory: $RESULTS_DIR"
    echo ""
    
    # List recent runs
    echo "Recent runs:"
    ls -lt "$RESULTS_DIR" 2>/dev/null | head -10 || echo "  No runs found"
    echo ""
    
    # Show latest result if available
    LATEST=$(ls -t "$RESULTS_DIR"/*.json 2>/dev/null | head -1)
    if [ -n "$LATEST" ]; then
      echo "Latest result: $LATEST"
      echo ""
      ${pkgs.jq}/bin/jq '.' "$LATEST" 2>/dev/null || cat "$LATEST"
    fi
  '';

in {
  imports = [
    ./vllm.nix
  ];

  # Add helper scripts to system packages
  environment.systemPackages = [
    pkgs.python312
    mini-agent
    swe-bench-run
    swe-bench-test
    swe-bench-setup
    swe-bench-status
    pkgs.jq
    pkgs.curl
    pkgs.git  # Required by mini-swe-agent for git operations
  ];

  # Ensure user can access docker/podman
  users.users.raj.extraGroups = lib.mkAfter [ "docker" ];

  # Create working directories
  systemd.tmpfiles.rules = [
    "d /home/raj/.mini-swe-agent 0755 raj users -"
  ];
}
