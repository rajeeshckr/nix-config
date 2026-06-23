{ pkgs, ... }:

{
  # ollama / LLM
  services.ollama = {
    enable = true;
    package = pkgs.unstable.ollama-cuda;
    port = 11434;
    host = "0.0.0.0";
    acceleration = "cuda";
    openFirewall = true;
    loadModels = [
      "deepseek-r1:14b"
      # Tool-calling model for the OpenClaw agent (see nixos/desktop/openclaw.nix);
      # deepseek-r1's <think> output is unsuitable as an agent/tool-calling model.
      "qwen2.5:7b"
    ];
  };
}
