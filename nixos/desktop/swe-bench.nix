# SWE-bench configuration for running AI coding benchmarks
# 
# This module sets up the environment for running SWE-bench evaluations
# using your local vLLM instance with Qwen2.5-Coder-14B.
#
# Usage:
#   1. Rebuild: sudo nixos-rebuild switch --flake .#nixos
#   2. Start vLLM: The container starts automatically (check with `docker ps`)
#   3. Run SWE-bench: Use the `swe-bench-run` command
#
{ config, lib, pkgs, ... }:

let
  # SWE-agent runner script
  swe-bench-run = pkgs.writeShellScriptBin "swe-bench-run" ''
    set -e
    
    VLLM_URL="''${VLLM_URL:-http://localhost:8000/v1}"
    MODEL_NAME="''${MODEL_NAME:-Qwen/Qwen2.5-Coder-14B-Instruct}"
    DATA_PATH="''${DATA_PATH:-princeton-nlp/SWE-bench_Lite}"
    
    echo "=== SWE-bench Runner ==="
    echo "vLLM URL: $VLLM_URL"
    echo "Model: $MODEL_NAME"
    echo "Dataset: $DATA_PATH"
    echo ""
    
    # Check if vLLM is running
    if ! curl -s "$VLLM_URL/models" > /dev/null 2>&1; then
      echo "Error: vLLM is not running at $VLLM_URL"
      echo "Start it with: docker start vllm"
      exit 1
    fi
    
    echo "vLLM is running. Available models:"
    curl -s "$VLLM_URL/models" | ${pkgs.jq}/bin/jq -r '.data[].id'
    echo ""
    
    # Run SWE-agent
    echo "Starting SWE-agent..."
    docker run -it --rm \
      --network host \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v "$HOME/.swe-agent:/root/.swe-agent" \
      -e OPENAI_API_KEY="not-needed" \
      sweagent/swe-agent:latest \
      run \
      --agent.model.name "openai:$MODEL_NAME" \
      --agent.model.base_url "$VLLM_URL" \
      --data_path "$DATA_PATH" \
      "$@"
  '';

  # Quick test script to verify setup
  swe-bench-test = pkgs.writeShellScriptBin "swe-bench-test" ''
    set -e
    
    VLLM_URL="''${VLLM_URL:-http://localhost:8000/v1}"
    
    echo "=== SWE-bench Setup Test ==="
    echo ""
    
    # Test 1: Check Docker
    echo "[1/4] Checking Docker..."
    if docker info > /dev/null 2>&1; then
      echo "  ✓ Docker is running"
    else
      echo "  ✗ Docker is not running"
      exit 1
    fi
    
    # Test 2: Check NVIDIA Container Toolkit
    echo "[2/4] Checking NVIDIA GPU access..."
    if docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi > /dev/null 2>&1; then
      echo "  ✓ GPU accessible from containers"
    else
      echo "  ✗ GPU not accessible (check nvidia-container-toolkit)"
      exit 1
    fi
    
    # Test 3: Check vLLM
    echo "[3/4] Checking vLLM..."
    if curl -s "$VLLM_URL/models" > /dev/null 2>&1; then
      MODEL=$(curl -s "$VLLM_URL/models" | ${pkgs.jq}/bin/jq -r '.data[0].id // "none"')
      echo "  ✓ vLLM running with model: $MODEL"
    else
      echo "  ✗ vLLM not responding at $VLLM_URL"
      echo "    Start with: docker start vllm"
      exit 1
    fi
    
    # Test 4: Quick inference test
    echo "[4/4] Testing inference..."
    RESPONSE=$(curl -s "$VLLM_URL/chat/completions" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "Qwen/Qwen2.5-Coder-14B-Instruct",
        "messages": [{"role": "user", "content": "Say hello"}],
        "max_tokens": 20
      }' | ${pkgs.jq}/bin/jq -r '.choices[0].message.content // "error"')
    
    if [ "$RESPONSE" != "error" ] && [ -n "$RESPONSE" ]; then
      echo "  ✓ Inference working: \"$RESPONSE\""
    else
      echo "  ✗ Inference failed"
      exit 1
    fi
    
    echo ""
    echo "=== All checks passed! ==="
    echo "Run 'swe-bench-run' to start benchmarking"
  '';

  # Pull required images
  swe-bench-setup = pkgs.writeShellScriptBin "swe-bench-setup" ''
    set -e
    
    echo "=== SWE-bench Setup ==="
    echo "Pulling required Docker images..."
    echo ""
    
    echo "[1/2] Pulling SWE-agent..."
    docker pull sweagent/swe-agent:latest
    
    echo ""
    echo "[2/2] Pulling vLLM (if not present)..."
    docker pull vllm/vllm-openai:latest
    
    echo ""
    echo "=== Setup complete! ==="
    echo ""
    echo "Next steps:"
    echo "  1. Run 'swe-bench-test' to verify everything works"
    echo "  2. Run 'swe-bench-run' to start benchmarking"
  '';

in {
  imports = [
    ./vllm.nix
  ];

  # Add helper scripts to system packages
  environment.systemPackages = [
    swe-bench-run
    swe-bench-test
    swe-bench-setup
    pkgs.jq
    pkgs.curl
  ];

  # Ensure user can access docker
  users.users.raj.extraGroups = lib.mkAfter [ "docker" ];

  # Create working directory for SWE-agent results
  systemd.tmpfiles.rules = [
    "d /home/raj/.swe-agent 0755 raj users -"
  ];
}
