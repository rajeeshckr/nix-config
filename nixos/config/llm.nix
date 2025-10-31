{ pkgs, ... }:

{
  # ollama / LLM
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    port = 11434;
    host = "0.0.0.0";
    acceleration = "cuda";
    openFirewall = true;
    loadModels = [
      "deepseek-r1:14b"
      "gemma3:12b"
    ];
  };
}
