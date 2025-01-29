{
  description = "A Nix-flake-based Node.js development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ self.overlays.default ];
            };
          }
        );
    in
    {
      overlays.default = _: prev: {
        nodejs = prev.nodejs;
      };

      devShells = forEachSupportedSystem (
        { pkgs }:
        let
          mkScript =
            name: text:
            let
              script = pkgs.writeShellScriptBin name text;
            in
            script;
          snippets = [
            (mkScript "prd" "pnpm run dev")
          ];
        in
        {
          # due to direnv [issue](https://github.com/direnv/direnv/issues/73)
          # we can not simply add alias in shellHook
          default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                node2nix
                nodejs
                nodePackages.pnpm
              ]
              ++ snippets;
            shellHook = ''
              export PATH="./node_modules/.bin:$PATH"
            '';
          };
        }
      );
    };
}
