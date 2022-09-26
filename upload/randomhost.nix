{ pkgs, ... }:

let 
  start = pkgs.writeShellScript "genhostname" ''
    hostname $(diceware -d - --no-caps -n 3)
  '';
in {
  systemd.services.randomhost = {
    wantedBy = [ "multi-user.target" ];
    before = [ "network-pre.target" ];
    wants = [ "network-pre.target" ];

    path = [ pkgs.diceware ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = start;
    };
  };
}