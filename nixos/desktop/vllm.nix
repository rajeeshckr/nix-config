{ config
, lib
, pkgs
, ... }:
let 
in {
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.oci-containers.containers = {
    vllm = {
      preRunExtraOptions = [
        "--runtime"
        "nvidia"
        "--gpus"
        "all"
      ];
      extraOptions = [
        "--ipc=host"
      ];
      cmd = [
        "serve"
        "mistralai/Mistral-Small-3.1-24B-Instruct-2503"
        "--tokenizer_mode" "mistral"
        "--config_format" "mistral"
        "--load_format" "mistral"
        "--tool-call-parser" "mistral"
        "--enable-auto-tool-choice"
        "--limit_mm_per_prompt"
        "image=10"
        "--tensor-parallel-size" "2"
      ];
      image = "vllm/vllm-openai:latest";
      ports = ["8000:8000"];
    };
  };
}