{ config
, lib
, pkgs
, ... }:
let 
  cfg = {
    model = "Qwen/Qwen2.5-Omni-7B";
    image = "vllm/vllm-openai:latest";
    port = 8000;
  };
in {
  hardware.nvidia-container-toolkit.enable = true;
  age.secrets.hugging-face-ro-token.file = ../../secrets/hugging-face-ro-token.age;
  virtualisation.oci-containers.containers = {
    vllm = {
      preRunExtraOptions = [
        "--storage-driver=overlay" # not sure why, but this gets blanked out
      ];
      environmentFiles = [config.age.secrets.hugging-face-ro-token.path];
      extraOptions = [
        "--ipc=host"
        "--device=nvidia.com/gpu=all"
      ];
      cmd = [
        "--model" cfg.model
        "--dtype=float16" # required for  NVIDIA GeForce RTX 2080 Ti
      ];
      image = cfg.image;
      ports = ["${toString cfg.port}:8000"];
    };
  };
}