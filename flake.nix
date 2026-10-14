{
  description = "Logos keycard_ui — the Keycard's app: its cards and the accounts it offers.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    keycard_shell_module = {
      url = "github:logos-co/logos-keycard-shell-module/b9c6b7c3323c231d05845736f841a2ed8cdbbe0d";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    # Pinned to the module's first branch until it reaches main.
    keycard_module = {
      url = "github:logos-co/logos-keycard-module/ea25bdf61f37a70eddaedacf67e41c85b2e5329f";
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
