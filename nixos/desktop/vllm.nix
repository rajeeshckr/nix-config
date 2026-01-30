{ config
, lib
, pkgs
, ... }:
let 
  cfg = {
    # Hermes-3-Llama-3.2-3B - Ungated Llama 3.2 fine-tune with 128K context
    # Same architecture as Llama-3.2-3B but without license gate
    model = "NousResearch/Hermes-3-Llama-3.2-3B";
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
        "--max-model-len" "50000"  # 50K context - safely fits in 6.64GB KV cache
        "--gpu-memory-utilization" "0.95"
      ];
      image = cfg.image;
      ports = ["${toString cfg.port}:8000"];
    };
  };
}
