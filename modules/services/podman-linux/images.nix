{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.podman;

  podman-lib = import ./podman-lib.nix { inherit pkgs lib config; };

  createQuadletSource = name: imageDef:
    let
      credsString =
        (if imageDef.username != null then imageDef.username else "")
        + (if imageDef.password != null then ":${imageDef.password}" else "");

      quadlet = podman-lib.deepMerge {
        Image = {
          AuthFile = imageDef.authFile;
          CertDir = imageDef.certDir;
          Creds = (if credsString != "" then credsString else null);
          DecryptionKey = imageDef.decryptionKeyFile;
          Image = imageDef.image;
          ImageTag = imageDef.tag;
          PodmanArgs = imageDef.extraPodmanArgs;
          TLSVerify = imageDef.tlsVerify;
        };
        Install = {
          WantedBy = optionals imageDef.autoStart [
            "default.target"
            "multi-user.target"
          ];
        };
        Service = {
          ExecStartPre = [ "${podman-lib.awaitPodmanUnshare}" ];
          TimeoutStartSec = 300;
          RemainAfterExit = "yes";
        };
        Unit = { Description = imageDef.description; };
      } imageDef.extraConfig;
    in ''
      # Automatically generated by home-manager for podman image configuration
      # DO NOT EDIT THIS FILE DIRECTLY
      #
      # ${name}.image
      ${podman-lib.toQuadletIni quadlet}
    '';

  toQuadletInternal = name: imageDef: {
    assertions = podman-lib.buildConfigAsserts name imageDef.extraConfig;
    serviceName =
      "podman-${name}"; # generated service name: 'podman-<name>-image.service
    source = podman-lib.removeBlankLines (createQuadletSource name imageDef);
    resourceType = "image";
  };
in let
  imageDefinitionType = types.submodule ({ name, ... }: {
    options = {
      autoStart = mkOption {
        type = types.bool;
        default = true;
        description =
          "Whether to pull the image on boot. Requires user lingering.";
      };

      authFile = mkOption {
        type = with types; nullOr path;
        default = null;
        description =
          "Path of the authentication file used to connect to registry.";
      };

      certDir = mkOption {
        type = with types; nullOr path;
        default = null;
        description =
          "Path of certificates (*.{crt,cert,key}) used to connect to registry.";
      };

      decryptionKeyFile = mkOption {
        type = with types; nullOr path;
        default = null;
        description = "Path to key used for decrpytion of images.";
      };

      description = mkOption {
        type = with types; nullOr str;
        default = "Service for image ${name}";
        defaultText = "Service for image \${name}";
        example = "My Image";
        description = "The description of the image.";
      };

      extraConfig = mkOption {
        type = podman-lib.extraConfigType;
        default = { };
        example = literalExpression ''
          {
            Image = {
              ContainersConfModule = "/etc/nvd.conf";
            };
          }
        '';
        description = "INI sections and values to populate the Image Quadlet.";
      };

      extraPodmanArgs = mkOption {
        type = with types; listOf str;
        default = [ ];
        example = [ "--os=linux" ];
        description =
          "Extra arguments to pass to the podman image pull command.";
      };

      image = mkOption {
        type = types.str;
        example = "quay.io/centos/centos:latest";
        description = "Image to pull.";
      };

      password = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "P@ssw0rd";
        description =
          "Password used to connect to registry. (Will be visible in nix store)";
      };

      tag = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "quay.io/centos/centos:latest";
        description =
          "FQIN of referenced Image when source is a file or directory archive.";
      };

      tlsVerify = mkOption {
        type = types.bool;
        default = true;
        description =
          "Require HTTPS and verification of certificates when contacting registries.";
      };

      username = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "bob";
        description = "Username used to connect to registry.";
      };

    };
  });
in {
  options.services.podman.images = mkOption {
    type = types.attrsOf imageDefinitionType;
    default = { };
    description = "Defines Podman image quadlet configurations.";
  };

  config = let imageQuadlets = mapAttrsToList toQuadletInternal cfg.images;
  in mkIf cfg.enable {
    services.podman.internal.quadletDefinitions = imageQuadlets;
    assertions = flatten (map (image: image.assertions) imageQuadlets);
  };
}
