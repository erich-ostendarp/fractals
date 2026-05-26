{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    unstable = nixpkgs-unstable.legacyPackages.${system};
  in {
    devShells.${system}.default = pkgs.mkShell {
      shellHook = ''
        export LIBGL_ALWAYS_SOFTWARE=1
      '';

      packages = with pkgs; [
        unstable.zls
        unstable.zig
        glfw
        libGL
      ];
    };
  };
}
