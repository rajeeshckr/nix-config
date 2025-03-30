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
      ];
      extraOptions = [
        "--ipc=host"
        "--device" "nvidia.com/gpu=all"
      ];
      cmd = [
        "--model" "mistralai/Mistral-Small-3.1-24B-Instruct-2503"
        "--tokenizer_mode" "mistral"
        "--config_format" "mistral"
        "--load_format" "mistral"
        "--tool-call-parser" "mistral"
        "--enable-auto-tool-choice"
        "--limit_mm_per_prompt"
        "--tensor-parallel-size" "2"
      ];
      image = "vllm/vllm-openai:latest";
      ports = ["8000:8000"];
    };
  };
}