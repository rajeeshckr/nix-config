{ config
, lib
, pkgs
, ... }:
let 
  cfg = {
    # Qwen2.5-Coder-14B-Instruct-AWQ - pre-quantized 4-bit, fits in 16GB
    # AWQ maintains good quality while using ~8GB VRAM
    model = "Qwen/Qwen2.5-Coder-14B-Instruct-AWQ";
    image = "vllm/vllm-openai:latest";
    port = 8000;
  };
in {
  hardware.nvidia-container-toolkit.enable = true;
  age.secrets.hugging-face-ro-token.file = ../../secrets/hugging-face-ro-token.age;
  virtualisation.oci-containers.containers = {
    vllm = {
      autoStart = true;
      preRunExtraOptions = [
        "--storage-driver=overlay" # not sure why, but this gets blanked out
      ];
      environmentFiles = [config.age.secrets.hugging-face-ro-token.path];
      environment = {
        PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
      };
      extraOptions = [
        "--ipc=host"
        "--device=nvidia.com/gpu=all"
      ];
      cmd = [
        "--model" cfg.model
        "--max-model-len" "32768"  # Qwen2.5-Coder supports 32K+, needed for SWE-bench
        "--gpu-memory-utilization" "0.95"  # Increased to fit larger KV cache
      ];
      image = cfg.image;
      ports = ["${toString cfg.port}:8000"];
    };
  };
}
