{ config
, lib
, pkgs
, ... }:
let 
  cfg = {
    # Qwen2.5-Coder-7B-Instruct-AWQ - 4-bit quantized (~4GB VRAM)
    # Best balance: good quality + plenty of room for 32K context on 16GB GPU
    model = "Qwen/Qwen2.5-Coder-7B-Instruct-AWQ";
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
        "--max-model-len" "32768"  # 32K context - AWQ leaves plenty of room
        "--gpu-memory-utilization" "0.90"
      ];
      image = cfg.image;
      ports = ["${toString cfg.port}:8000"];
    };
  };
}
