use std::fs;
use std::ops::Deref;
use std::os::unix::fs::MetadataExt;
use std::{env, vec};

use color_eyre::eyre::{bail, Context};
use color_eyre::Result;

use tracing::{debug, info, warn};

use crate::interface::NHRunnable;
use crate::interface::OsRebuildType::{self, Boot, Build, Switch, Test};
use crate::interface::{self, OsRebuildArgs};
use crate::util::{compare_semver, get_nix_version};
use crate::*;

const SYSTEM_PROFILE: &str = "/nix/var/nix/profiles/system";
const CURRENT_PROFILE: &str = "/run/current-system";

const SPEC_LOCATION: &str = "/etc/specialisation";

impl NHRunnable for interface::OsArgs {
    fn run(&self) -> Result<()> {
        match &self.action {
            Switch(args) | Boot(args) | Test(args) | Build(args) => args.rebuild(&self.action),
            s => bail!("Subcommand {:?} not yet implemented", s),
        }
    }
}

impl OsRebuildArgs {
    pub fn rebuild(&self, rebuild_type: &OsRebuildType) -> Result<()> {
        let use_sudo = if self.bypass_root_check {
            warn!("Bypassing root check, now running nix as root");
            !nix::unistd::Uid::effective().is_root()
        } else {
            if nix::unistd::Uid::effective().is_root() {
                bail!("Don't run nh os as root. I will call sudo internally as needed");
            }
            true
        };

        let hostname = match &self.hostname {
            Some(h) => h.to_owned(),
            None => hostname::get().context("Failed to get hostname")?,
        };

        let out_path: Box<dyn crate::util::MaybeTempPath> = match self.common.out_link {
            Some(ref p) => Box::new(p.clone()),
            None => Box::new({
                let dir = tempfile::Builder::new().prefix("nh-os").tempdir()?;
                (dir.as_ref().join("result"), dir)
            }),
        };

        debug!(?out_path);

        let flake_metadata =
            fs::metadata(&self.common.flakeref).context("Failed to get metadata of flake")?;
        let flake_uid = nix::unistd::Uid::from_raw(flake_metadata.uid());
        debug!("flakeref is owned by root: {:?}", flake_uid.is_root());

        // if we are root, then we do not need to elevate
        // if we are not root, and the flake is owned by root, then we need to elevate
        let elevation_required = use_sudo && flake_uid.is_root();

        if self.common.pull {
            commands::CommandBuilder::default()
                .root(elevation_required)
                .args(["git", "-C", &self.common.flakeref, "pull"])
                .message("Pulling flake")
                .build()?
                .exec()?;
        }

        #[cfg(target_os = "linux")]
        let configuration_module = "nixosConfigurations";
        #[cfg(target_os = "macos")]
        let configuration_module = "darwinConfigurations";

        let flake_output = format!(
            "{}#{configuration_module}.\"{hostname:?}\".config.system.build.toplevel",
            &self.common.flakeref.deref()
        );

        if self.common.update {
            // Get the Nix version
            let nix_version = get_nix_version().unwrap_or_else(|_| {
                panic!("Failed to get Nix version. Custom Nix fork?");
            });

            // Default interface for updating flake inputs
            let mut update_args = vec!["nix", "flake", "update"];

            // If user is on Nix 2.19.0 or above, --flake must be passed
            if let Ok(ordering) = compare_semver(&nix_version, "2.19.0") {
                if ordering == std::cmp::Ordering::Greater {
                    update_args.push("--flake");
                }
            }

            update_args.push(&self.common.flakeref);

            debug!("nix_version: {:?}", nix_version);
            debug!("update_args: {:?}", update_args);

            commands::CommandBuilder::default()
                .root(elevation_required)
                .args(&update_args)
                .message("Updating flake")
                .build()?
                .exec()?;
        }

        #[cfg(target_os = "linux")]
        let message = "Building NixOS configuration";
        #[cfg(target_os = "macos")]
        let message = "Building Darwin configuration";

        commands::BuildCommandBuilder::default()
            .flakeref(flake_output)
            .message(message)
            .extra_args(["--out-link"])
            .extra_args([out_path.get_path()])
            .extra_args(&self.extra_args)
            .nom(!self.common.no_nom)
            .build()?
            .exec()?;

        let current_specialisation = std::fs::read_to_string(SPEC_LOCATION).ok();

        let target_specialisation = if self.no_specialisation {
            None
        } else {
            current_specialisation.or_else(|| self.specialisation.to_owned())
        };

        debug!("target_specialisation: {target_specialisation:?}");

        let target_profile = match &target_specialisation {
            None => out_path.get_path().to_owned(),
            Some(spec) => out_path.get_path().join("specialisation").join(spec),
        };

        target_profile.try_exists().context("Doesn't exist")?;

        commands::CommandBuilder::default()
            .args(self.common.diff_provider.split_ascii_whitespace())
            .args([CURRENT_PROFILE, target_profile.to_str().unwrap()])
            .message("Comparing changes")
            .build()?
            .exec()?;

        if self.common.dry || matches!(rebuild_type, OsRebuildType::Build(_)) {
            return Ok(());
        }

        if self.common.ask {
            info!("Apply the config?");
            let confirmation = dialoguer::Confirm::new().default(false).interact()?;

            if !confirmation {
                bail!("User rejected the new config");
            }
        }

        #[cfg(target_os = "linux")]
        if let Test(_) | Switch(_) = rebuild_type {
            // !! Use the target profile aka spec-namespaced
            let switch_to_configuration =
                target_profile.join("bin").join("switch-to-configuration");
            let switch_to_configuration = switch_to_configuration.to_str().unwrap();

            commands::CommandBuilder::default()
                .root(use_sudo)
                .args([switch_to_configuration, "test"])
                .message("Activating configuration")
                .build()?
                .exec()?;
        }

        if let Boot(_) | Switch(_) = rebuild_type {
            commands::CommandBuilder::default()
                .root(use_sudo)
                .args(["nix-env", "--profile", SYSTEM_PROFILE, "--set"])
                .args([out_path.get_path()])
                .build()?
                .exec()?;

            // !! Use the base profile aka no spec-namespace
            #[cfg(target_os = "linux")]
            {
                let switch_to_configuration = out_path
                    .get_path()
                    .join("bin")
                    .join("switch-to-configuration");
                let switch_to_configuration = switch_to_configuration.to_str().unwrap();

                commands::CommandBuilder::default()
                    .root(use_sudo)
                    .args([switch_to_configuration, "boot"])
                    .message("Adding configuration to bootloader")
                    .build()?
                    .exec()?;
            }

            #[cfg(target_os = "macos")]
            {
                let activate_user = out_path.get_path().join("activate-user");
                let activate_user = activate_user.to_str().unwrap();

                commands::CommandBuilder::default()
                    .args([activate_user])
                    .message("Activating configuration for user")
                    .build()?
                    .exec()?;

                let activate = out_path.get_path().join("activate");
                let activate = activate.to_str().unwrap();

                commands::CommandBuilder::default()
                    .root(use_sudo)
                    .args([activate])
                    .message("Activating configuration")
                    .build()?
                    .exec()?;
            }
        }

        // Make sure out_path is not accidentally dropped
        // https://docs.rs/tempfile/3.12.0/tempfile/index.html#early-drop-pitfall
        drop(out_path);

        Ok(())
    }
}
