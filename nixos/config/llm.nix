{ pkgs, ... }:

{
  # ollama / LLM
  services.ollama = {
    enable = true;
    port = 11434;
    host = "0.0.0.0";
    acceleration = "cuda";
    openFirewall = true;
    loadModels = [
      "deepseek-r1:32b"
    ];
    environmentVariables = {
      OLLAMA_ORIGINS = "http://sauron.middleearth.samlockart.com";
      OLLAMA_DEBUG = "true";
      OLLAMA_FLASH_ATTENTION = "1";
    };
  };
}