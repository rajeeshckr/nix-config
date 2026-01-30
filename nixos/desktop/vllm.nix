{ config
, lib
, pkgs
, ... }:
let 
  cfg = {
    # Qwen2.5-Coder-14B is optimal for 16GB VRAM - great for code tasks & SWE-bench
    model = "Qwen/Qwen2.5-Coder-14B-Instruct";
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
        "--max-model-len" "4096"
        "--gpu-memory-utilization=0.85"
        "--dtype=float16"
      ];
      image = cfg.image;
      ports = ["${toString cfg.port}:8000"];
    };
  };
}
