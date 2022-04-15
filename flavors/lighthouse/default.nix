# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit(lib)
    optional optionals optionalString optionalAttrs
    elem mapAttrs mapAttrs' nameValuePair filterAttrs
    attrNames getAttrs flatten remove
    mkIf mkMerge mkDefault mkForce
    importJSON toLower hasPrefix removePrefix;

  AndroidtoLighthouse = {
    "12" = "sailboat";
  };

  LighthousetoAndroid = mapAttrs' (name: value: nameValuePair value name) AndroidtoLighthouse;

  deviceMetadata = lib.importJSON ./device-metadata.json;
  LighthouseRelease = AndroidtoLighthouse.${builtins.toString config.androidVersion};
  repoDirs = lib.importJSON (./. + "/${LighthouseRelease}/repo.json");
  _deviceDirs = importJSON (./. + "/${LighthouseRelease}/device-dirs.json");
  vendorDirs = importJSON (./. + "/${LighthouseRelease}/vendor-dirs.json");

  # TODO: Move this filtering into vanilla/graphene
  filterDirAttrs = dir: filterAttrs (n: v: elem n [ "rev" "sha256" "url" "patches" "postPatch" ]) dir;
  filterDirsAttrs = dirs: mapAttrs (n: v: filterDirAttrs v) dirs;
in
mkIf (config.flavor == "Lighthouse")
  {
    androidVersion =
      let
        defaultBranch = deviceMetadata.${config.device}.branch;
      in
        mkIf (deviceMetadata ? ${config.device}) (mkDefault (lib.toInt LighthousetoAndroid.${defaultBranch}));
    flavorVersion = removePrefix "lighthouse-" AndroidtoLighthouse.${toString config.androidVersion};

    productNamePrefix = "lighthouse_"; # product names start with "lineage_"

    buildDateTime = mkDefault 1644929759;

  # LineageOS uses this by default. If your device supports it, I recommend using variant = "user"
  variant = mkDefault "userdebug";

  warnings = optional
    (
      (config.device != null) &&
      !(elem config.device supportedDevices) &&
      (config.deviceFamily != "generic")
    )
    "${config.device} is not an officially-supported device for Lighthouse";

  source.dirs = mkMerge ([
    repoDirs

    {
      "vendor/lineage".patches = [
        ./0003-kernel-Set-constant-kernel-timestamp.patch
      ];
      "system/extras".patches = [
        # pkgutil.get_data() not working, probably because we don't use their compiled python
      ];
      # LineageOS will sometimes force-push to this repo, and the older revisions are garbage collected.
      # So we'll just build chromium webview ourselves.
      "external/chromium-webview".enable = false;
    }
  ] ++ optionals (deviceMetadata ? "${config.device}") [
    # Device-specific source dirs
    (
      let
        vendor = toLower deviceMetadata.${config.device}.vendor;
        relpathWithDependencies = relpath: [ relpath ] ++ (flatten (map (p: relpathWithDependencies p) deviceDirs.${relpath}.deps));
        relpaths = relpathWithDependencies "device/${vendor}/${config.device}";
        filteredRelpaths = remove (attrNames repoDirs) relpaths; # Remove any repos that we're already including from repo json
      in
      filterDirsAttrs (getAttrs filteredRelpaths deviceDirs)
    )

    # Vendor-specific source dirs
    (
      let
        _vendor = toLower deviceMetadata.${config.device}.vendor;
        vendor = if config.device == "shamu" then "motorola" else _vendor;
        relpath = "vendor/${vendor}";
      in
      filterDirsAttrs (getAttrs [ relpath ] vendorDirs)
    )
  ] ++ optional (config.device == "bacon")
    # Bacon needs vendor/oppo in addition to vendor/oneplus
    # See https://github.com/danielfullmer/robotnix/issues/26
    (filterDirsAttrs (getAttrs [ "vendor/oppo" ] vendorDirs))
  );

  source.manifest.url = mkDefault "https://github.com/lighthouse-os/manifest.git";
  source.manifest.rev = mkDefault "refs/heads/${LighthouseRelease}";

  # Enable robotnix-built chromium / webview
  apps.chromium.enable = mkDefault true;
  webview.chromium.availableByDefault = mkDefault true;
  webview.chromium.enable = mkDefault true;

  # This is the prebuilt webview apk from LineageOS. Adding this here is only
  # for convenience if the end-user wants to set `webview.prebuilt.enable = true;`.
  webview.prebuilt.apk = config.source.dirs."external/chromium-webview".src + "/prebuilt/${config.arch}/webview.apk";
  webview.prebuilt.availableByDefault = mkDefault true;
  removedProductPackages = [ "webview" ];

  # Needed by included kernel build for some devices (pioneer at least)
  envPackages = [ pkgs.openssl.dev ] ++ optionals (config.androidVersion >= 11) [ pkgs.gcc.cc pkgs.glibc.dev ];

  envVars.RELEASE_TYPE = mkDefault "EXPERIMENTAL"; # Other options are RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL

  # LineageOS flattens all APEX packages: https://review.lineageos.org/c/LineageOS/android_vendor_lineage/+/270212
  #signing.apex.enable = false;
  # This environment variable is set in android/build.sh under https://github.com/lineageos-infra/build-config
  #envVars.OVERRIDE_TARGET_FLATTEN_APEX = "true";

  # LineageOS needs this additional command line argument to enable
  # backuptool.sh, which runs scripts under /system/addons.d
  # otaArgs = [ "--backup=true" ];
}

