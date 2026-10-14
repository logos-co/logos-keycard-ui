{
  description = "Logos keycard_ui — the Keycard's app: its cards and the accounts it offers.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    keycard_shell_module = {
      url = "github:logos-co/logos-keycard-shell-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    keycard_module = {
      url = "github:logos-co/logos-keycard-module";
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
