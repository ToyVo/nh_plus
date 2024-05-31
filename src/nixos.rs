use std::fs;
use std::ops::Deref;
use std::os::unix::fs::MetadataExt;

use color_eyre::eyre::{bail, Context};
use color_eyre::Result;

use tracing::{debug, info};

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
        let effective_uid = nix::unistd::Uid::effective();
        let effective_gid = nix::unistd::Gid::effective();

        let hostname = match &self.hostname {
            Some(h) => h.to_owned(),
            None => hostname::get().context("Failed to get hostname")?,
        };

        let out_dir = tempfile::Builder::new().prefix("nh-os-").tempdir()?;
        let out_link = out_dir.path().join("result");
        let out_link_str = out_link.to_str().unwrap();
        debug!("out_dir: {:?}", out_dir);
        debug!("out_link {:?}", out_link);

        let flake_metadata =
            fs::metadata(&self.flakeref).context("Failed to get metadata of flake")?;
        let flake_uid = nix::unistd::Uid::from_raw(flake_metadata.uid());
        debug!("flakeref is owned by root: {:?}", flake_uid.is_root());

        // if we are root, then we do not need to elevate
        // if we are not root, and the flake is owned by root, then we need to elevate
        let elevation_required = !effective_uid.is_root() && flake_uid.is_root();

        if self.common.pull {
            commands::CommandBuilder::default()
                .root(elevation_required)
                .args(["git", "-C", &self.flakeref, "pull"])
                .message("Pulling flake")
                .build()?
                .exec()?;
        }

        #[cfg(target_os = "linux")]
        let configuration_module = "nixosConfigurations";
        #[cfg(target_os = "macos")]
        let configuration_module = "darwinConfigurations";

        let flake_output = format!(
            "{}#{configuration_module}.{hostname:?}.config.system.build.toplevel",
            &self.flakeref.deref()
        );

        if self.common.update {
            // Get the Nix version
            let nix_version = get_nix_version().unwrap_or_else(|_| {
                panic!("Failed to get Nix version. Custom Nix fork?");
            });

            let status = commands::CommandBuilder::default()
                .args(["git", "-C", &self.flakeref, "diff", "--name-only", "--diff-filter=U"])
                .message("Checking for conflicts")
                .build()?
                .exec_capture()?;

            if let Some(conflict) = status {
                if conflict == "flake.lock\n".to_string() {
                    commands::CommandBuilder::default()
                        .args(["git", "-C", &self.flakeref, "reset", "flake.lock"])
                        .message("Resetting flake.lock")
                        .build()?
                        .exec()?;
                    commands::CommandBuilder::default()
                        .args(["git", "-C", &self.flakeref, "checkout", "flake.lock"])
                        .message("Checking out flake.lock")
                        .build()?
                        .exec()?;
                } else if conflict != "" {
                    panic!("Conflicts dectected that were more than just flake.lock, {conflict:?}");
                }
            }

            // Default interface for updating flake inputs
            let mut update_args = vec!["nix", "flake", "update"];

            // If user is on Nix 2.19.0 or above, --flake must be passed
            if let Ok(ordering) = compare_semver(&nix_version, "2.19.0") {
                if ordering == std::cmp::Ordering::Greater {
                    update_args.push("--flake");
                }
            }

            update_args.push(&self.flakeref);

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
            .extra_args(["--out-link", out_link_str])
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
            None => out_link.to_owned(),
            Some(spec) => out_link.join("specialisation").join(spec),
        };

        target_profile.try_exists().context("Doesn't exist")?;

        commands::CommandBuilder::default()
            .args(self.common.diff_provider.split_ascii_whitespace())
            .args([
                CURRENT_PROFILE,
                target_profile.to_str().unwrap(),
            ])
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
                return Ok(());
            }
        }

        #[cfg(target_os = "linux")]
        if let Test(_) | Switch(_) = rebuild_type {
            // !! Use the target profile aka spec-namespaced
            let switch_to_configuration =
                target_profile.join("bin").join("switch-to-configuration");
            let switch_to_configuration = switch_to_configuration.to_str().unwrap();

            commands::CommandBuilder::default()
                .root(!effective_uid.is_root())
                .args([switch_to_configuration, "test"])
                .message("Activating configuration")
                .build()?
                .exec()?;
        }

        if let Boot(_) | Switch(_) = rebuild_type {
            let profile_metadata =
                fs::metadata(SYSTEM_PROFILE).context("Failed to get metadata of profile")?;
            let profile_uid = nix::unistd::Uid::from_raw(profile_metadata.uid());
            let profile_gid = nix::unistd::Gid::from_raw(profile_metadata.gid());
            let can_write = !profile_metadata.permissions().readonly() && (effective_uid == profile_uid || effective_gid == profile_gid);
            debug!("${SYSTEM_PROFILE} is writable by user: {can_write}");

            commands::CommandBuilder::default()
                .root(!effective_uid.is_root() && !can_write)
                .args([
                    "nix-env",
                    "--profile",
                    SYSTEM_PROFILE,
                    "--set",
                    out_link_str,
                ])
                .build()?
                .exec()?;

            // !! Use the base profile aka no spec-namespace
            #[cfg(target_os = "linux")]
            {
                let switch_to_configuration = out_link.join("bin").join("switch-to-configuration");
                let switch_to_configuration = switch_to_configuration.to_str().unwrap();

                commands::CommandBuilder::default()
                    .root(!effective_uid.is_root())
                    .args([switch_to_configuration, "boot"])
                    .message("Adding configuration to bootloader")
                    .build()?
                    .exec()?;
            }

            #[cfg(target_os = "macos")]
            {
                let activate_user = out_link.join("activate-user");
                let activate_user = activate_user.to_str().unwrap();

                commands::CommandBuilder::default()
                    .args([activate_user])
                    .message("Activating configuration for user")
                    .build()?
                    .exec()?;

                let activate = out_link.join("activate");
                let activate = activate.to_str().unwrap();

                commands::CommandBuilder::default()
                    .root(!effective_uid.is_root())
                    .args([activate])
                    .message("Activating configuration")
                    .build()?
                    .exec()?;
            }
        }

        // Drop the out dir *only* when we are finished
        drop(out_dir);

        Ok(())
    }
}
