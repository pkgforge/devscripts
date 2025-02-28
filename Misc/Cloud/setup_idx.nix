{ pkgs, ... }: {
  channel = "unstable";
  packages = [
  ];
  env = { };
  idx = {
    extensions = [
    ];
    previews = {
      enable = true;
      previews = { };
    };
    #Workspace lifecycle hooks
    workspace = {
      onCreate = {
        default.openFiles = [ ".idx/dev.nix" "README.md" ];
      };
      #Runs when the workspace is (re)started
      onStart = {
        #Install SOAR and ensure it's in the PATH
        setup = ''
         #Debloat
          rm -rf "$HOME/.android"* 2>/dev/null
          rm -rf "$HOME/.emu" 2>/dev/null
          rm -rf "$HOME/.npm" 2>/dev/null

         #Install SOAR
          curl -fsSL 'https://soar.qaidvoid.dev/install.sh' | sh
          mkdir -p "$HOME/.local/share/soar/bin"
          if [ -f "./soar" ]; then
            mv "./soar" "$HOME/.local/share/soar/bin/soar"
            chmod +x "$HOME/.local/share/soar/bin/soar"
            if [ ! -s "$HOME/.config/soar/config.toml" ]; then
              "$HOME/.local/share/soar/bin/soar" defconfig --external
            fi
          fi
          if [ -f "$HOME/.bashrc" ]; then
            if ! grep -q "export PATH=\$PATH:\$HOME/.local/share/soar/bin" "$HOME/.bashrc"; then
              echo 'export PATH=$PATH:$HOME/.local/share/soar/bin' >> "$HOME/.bashrc"
            fi
          fi
          export PATH="$PATH:$HOME/.local/share/soar/bin"
        '';
      };
    };
  };
}
