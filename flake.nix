{
  description = "Logos keycard_ui — the Keycard's app: its cards and the accounts it offers.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Pinned to the module's first branch until it reaches main.
    keycard_module = {
      url = "github:logos-co/logos-keycard-module/bb411282947c74a89b18e1d4ba65196a0c8216d4";
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
