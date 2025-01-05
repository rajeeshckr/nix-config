{ pkgs, ... }: {
  programs.k9s = {
    enable = true;
    plugin = {
      plugins = {
        ng-recreate = {
          shortCut = "Ctrl+O";
          description = "Recreate nodegroup";
          scopes = ["ng" "nodegroup"];
          background = true;
          command = "kubectl";
          args = [
            "annotate"
            "$RESOURCENAME"
            "-n"
            "$NAMESPACE"
            "nodegroup-operator.compute.zende.sk/restarted-at=now"
            "--as=admin"
            "--as-group=system:masters"
            "-c"
            "$CONTEXT"
          ];
        };
      };
    };
  };
}