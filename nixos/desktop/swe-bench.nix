# SWE-bench configuration for running AI coding benchmarks
# 
# This module sets up mini-swe-agent for running SWE-bench evaluations
# using your local vLLM instance with Qwen2.5-Coder-14B.
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
  # Python environment with pip for installing mini-swe-agent
  pythonEnv = pkgs.python312.withPackages (ps: with ps; [
    pip
    virtualenv
  ]);

  # mini-swe-agent runner script for interactive use
  mini-agent = pkgs.writeShellScriptBin "mini-agent" ''
    set -e
    
    export OPENAI_API_KEY="''${OPENAI_API_KEY:-not-needed}"
    export OPENAI_BASE_URL="''${OPENAI_BASE_URL:-http://localhost:8000/v1}"
    MODEL_NAME="''${MODEL_NAME:-Qwen/Qwen2.5-Coder-14B-Instruct}"
    
    # Add user bin to PATH
    export PATH="$HOME/.local/bin:$PATH"
    
    # Check if mini-swe-agent is installed
    if ! command -v mini &> /dev/null; then
      echo "mini-swe-agent not found. Run 'swe-bench-setup' first."
      exit 1
    fi
    
    # Check if vLLM is running
    if ! curl -s "$OPENAI_BASE_URL/models" > /dev/null 2>&1; then
      echo "Warning: vLLM not responding at $OPENAI_BASE_URL"
      echo "Start it with: docker start vllm"
      echo ""
    fi
    
    # Run mini-swe-agent with visual UI
    exec mini -v --model "$MODEL_NAME" "$@"
  '';

  # SWE-bench benchmark runner
  swe-bench-run = pkgs.writeShellScriptBin "swe-bench-run" ''
    set -e
    
    export OPENAI_API_KEY="''${OPENAI_API_KEY:-not-needed}"
    export OPENAI_BASE_URL="''${OPENAI_BASE_URL:-http://localhost:8000/v1}"
    MODEL_NAME="''${MODEL_NAME:-Qwen/Qwen2.5-Coder-14B-Instruct}"
    DATASET="''${DATASET:-princeton-nlp/SWE-bench_Lite}"
    
    # Add user bin to PATH
    export PATH="$HOME/.local/bin:$PATH"
    
    echo "=== SWE-bench Runner (mini-swe-agent) ==="
    echo "vLLM URL: $OPENAI_BASE_URL"
    echo "Model: $MODEL_NAME"
    echo "Dataset: $DATASET"
    echo ""
    
    # Check if mini-swe-agent is installed
    if ! command -v mini-swebench &> /dev/null; then
      echo "mini-swe-agent not found. Run 'swe-bench-setup' first."
      exit 1
    fi
    
    # Check if vLLM is running
    if ! curl -s "$OPENAI_BASE_URL/models" > /dev/null 2>&1; then
      echo "Error: vLLM is not running at $OPENAI_BASE_URL"
      echo "Start it with: docker start vllm"
      exit 1
    fi
    
    echo "vLLM is running. Available models:"
    curl -s "$OPENAI_BASE_URL/models" | ${pkgs.jq}/bin/jq -r '.data[].id'
    echo ""
    
    # Run SWE-bench evaluation
    echo "Starting SWE-bench evaluation..."
    exec mini-swebench \
      --model "$MODEL_NAME" \
      --dataset "$DATASET" \
      "$@"
  '';

  # Quick test script to verify setup
  swe-bench-test = pkgs.writeShellScriptBin "swe-bench-test" ''
    set -e
    
    export OPENAI_API_KEY="''${OPENAI_API_KEY:-not-needed}"
    export OPENAI_BASE_URL="''${OPENAI_BASE_URL:-http://localhost:8000/v1}"
    MODEL_NAME="''${MODEL_NAME:-Qwen/Qwen2.5-Coder-14B-Instruct}"
    
    # Add user bin to PATH
    export PATH="$HOME/.local/bin:$PATH"
    
    echo "=== SWE-bench Setup Test ==="
    echo ""
    
    # Test 1: Check Docker
    echo "[1/5] Checking Docker..."
    if docker info > /dev/null 2>&1; then
      echo "  ✓ Docker is running"
    else
      echo "  ✗ Docker is not running"
      exit 1
    fi
    
    # Test 2: Check NVIDIA Container Toolkit
    echo "[2/5] Checking NVIDIA GPU access..."
    if docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi > /dev/null 2>&1; then
      echo "  ✓ GPU accessible from containers"
    else
      echo "  ✗ GPU not accessible (check nvidia-container-toolkit)"
      exit 1
    fi
    
    # Test 3: Check vLLM
    echo "[3/5] Checking vLLM..."
    if curl -s "$OPENAI_BASE_URL/models" > /dev/null 2>&1; then
      MODEL=$(curl -s "$OPENAI_BASE_URL/models" | ${pkgs.jq}/bin/jq -r '.data[0].id // "none"')
      echo "  ✓ vLLM running with model: $MODEL"
    else
      echo "  ✗ vLLM not responding at $OPENAI_BASE_URL"
      echo "    Start with: docker start vllm"
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
    if command -v mini &> /dev/null; then
      VERSION=$(mini --version 2>/dev/null || echo "installed")
      echo "  ✓ mini-swe-agent: $VERSION"
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

  # Setup script to install mini-swe-agent
  swe-bench-setup = pkgs.writeShellScriptBin "swe-bench-setup" ''
    set -e
    
    echo "=== SWE-bench Setup (mini-swe-agent) ==="
    echo ""
    
    echo "[1/2] Installing mini-swe-agent..."
    pip install --user --upgrade mini-swe-agent
    
    # Ensure ~/.local/bin is in PATH for current session
    export PATH="$HOME/.local/bin:$PATH"
    
    # Check if it works
    if command -v mini &> /dev/null; then
      echo "  ✓ mini-swe-agent installed successfully"
    else
      echo ""
      echo "  Add this to your ~/.bashrc or ~/.zshrc:"
      echo '    export PATH="$HOME/.local/bin:$PATH"'
      echo ""
    fi
    
    echo ""
    echo "[2/2] Pulling vLLM Docker image (if not present)..."
    docker pull vllm/vllm-openai:latest
    
    echo ""
    echo "=== Setup complete! ==="
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

  # Add helper scripts and Python to system packages
  environment.systemPackages = [
    pythonEnv
    mini-agent
    swe-bench-run
    swe-bench-test
    swe-bench-setup
    swe-bench-status
    pkgs.jq
    pkgs.curl
    pkgs.git  # Required by mini-swe-agent for git operations
  ];

  # Ensure user can access docker
  users.users.raj.extraGroups = lib.mkAfter [ "docker" ];

  # Create working directories
  systemd.tmpfiles.rules = [
    "d /home/raj/.mini-swe-agent 0755 raj users -"
  ];
}
