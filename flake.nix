{
  description = "Logos keycard_ui — the Keycard's app: its cards and the accounts it offers.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Pinned to logos-keycard-shell-module#3's head until it merges; then follow main.
    keycard_shell_module = {
      url = "github:logos-co/logos-keycard-shell-module/7d3e803d23755e080b87f2880e175fd035aa7ccf";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    # Pinned to logos-keycard-module#3's head until it merges; then follow main.
    keycard_module = {
      url = "github:logos-co/logos-keycard-module/5532778174c021e6f52a449920530abe5a4186de";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  # mkLogosQmlModule assembles the QML into the package, which the .lgx step needs.
  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
