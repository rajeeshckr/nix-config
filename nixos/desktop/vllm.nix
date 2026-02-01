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
        "--max-model-len" "80000"  # ~80K context with FP8 KV cache
        "--gpu-memory-utilization" "0.90"  # Leave headroom for sampler/ops
        "--kv-cache-dtype" "fp8_e5m2"  # ~50% KV cache memory reduction
        "--enable-chunked-prefill"  # Better memory efficiency for long prompts
        "--max-num-seqs" "32"  # Reduce concurrent sequences (default 256)
      ];
      image = cfg.image;
      ports = ["${toString cfg.port}:8000"];
    };
  };
}
