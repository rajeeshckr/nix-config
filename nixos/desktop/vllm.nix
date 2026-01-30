{ config
, lib
, pkgs
, ... }:
let 
  cfg = {
    # Qwen2.5-Coder-7B-Instruct - Full precision FP16 for best quality
    # 7B fits comfortably in 16GB VRAM with room for KV cache
    model = "Qwen/Qwen2.5-Coder-7B-Instruct";
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
        "--max-model-len" "16384"  # 16K context - balanced for FP16 7B model
        "--gpu-memory-utilization" "0.95"
      ];
      image = cfg.image;
      ports = ["${toString cfg.port}:8000"];
    };
  };
}
