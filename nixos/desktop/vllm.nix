{ config
, lib
, pkgs
, ... }:
let 
  cfg = {
    model = "mistralai/Mistral-Small-3.1-24B-Instruct-2503";
    image = "vllm/vllm-openai:latest";
    port = 8000;
  };
in {
  hardware.nvidia-container-toolkit.enable = true;
  age.secrets.hugging-face-ro-token.file = ../../secrets/borg.age;
  virtualisation.oci-containers.containers = {
    vllm = {
      preRunExtraOptions = [
        "--storage-driver=overlay" # not sure why, but this gets blanked out
      ];
      environmentFiles = [age.secrets.hugging-face-ro-token.path];
      extraOptions = [
        "--ipc=host"
        "--device=nvidia.com/gpu=all"
      ];
      cmd = [
        "--model" cfg.model
        "--tokenizer_mode" "mistral"
        "--config_format" "mistral"
        "--load_format" "mistral"
        "--tool-call-parser" "mistral"
        "--enable-auto-tool-choice"
        "--limit_mm_per_prompt" "image=10"
        "--tensor-parallel-size" "2"
      ];
      image = cfg.image;
      ports = ["${toString cfg.port}:8000"];
    };
  };
}