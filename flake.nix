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
    # metadata.json depends on signer_manager_module; the builder needs its LIDL.
    signer_manager_module = {
      url = "github:logos-co/logos-signer-manager-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.keycard_module.follows = "keycard_module";
      inputs.keycard_shell_module.follows = "keycard_shell_module";
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
