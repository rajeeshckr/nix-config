{ pkgs, ... }: {
  programs.k9s = {
    enable = true;
    settings = {};
    plugin = {
      plugins = {
        # currently requires launching a new terminal instance
        # as k9s doesn't support interactive plugins (from what I can tell)
        # should work with iterm2/other terminals also
        ssm-ssh = {
          shortCut = "s";
          description = "SSH into a node (requires AWS auth and kitty)";
          scopes = ["node"];
          background = true;
          command = "sh";
          args = [
            "-c"
            ''
              kubectl get $RESOURCE_NAME $NAME \
                --output=jsonpath="{.metadata.labels.topology\.kubernetes\.io/region}" \
                | xargs printf "AWS_REGION=%s ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error ubuntu_ssm_sudo@$NAME" \
                | xargs -I{} kitty --title "$NAME" sh -c '{}'
            ''
          ];
        };

        kube-drain = {
          shortCut = "a";
          description = "Drain and shutdown a node using kube-drain";
          scopes = ["node"];
          background = true;
          command = "sh";
          args = [
            "-c"
            ''
              kitty --title "kube-drain - $NAME" sh -c 'kube-drain $NAME --as admin --as-group system:masters'
            ''
          ];
        };

        ng-recreate = {
          shortCut = "Ctrl-O";
          description = "Recreate nodegroup";
          scopes = ["ng" "nodegroup"];
          background = true;
          command = "bash";
          args = [
            "-c"
            ''
              kubectl annotate --as=admin --as-group=system:masters $RESOURCE_NAME $NAME \
                -n $NAMESPACE \
                "nodegroup-operator.compute.zende.sk/restarted-at=$(date +"%Y-%m-%dT%H:%M:%S%z")"
            ''
          ];
        };
      };
    };
  };
}