use std::{env::var_os, path::PathBuf};

use etcetera::{app_strategy::Xdg, AppStrategy, AppStrategyArgs, HomeDirError};

#[derive(Debug)]
pub struct Config {
    pub os_flake: PathBuf,
    pub home_flake: PathBuf,
}

impl Config {
    pub fn from_env() -> Result<Self, HomeDirError> {
        let flake = var_os("NH_FLAKE").or_else(|| var_os("FLAKE"));
        let os_flake = var_os("NH_OS_FLAKE")
            .or_else(|| flake.clone())
            .map_or_else(
                || {
                    if cfg!(target_os = "macos") {
                        Xdg::new(AppStrategyArgs {
                            app_name: "nix-darwin".to_owned(),
                            ..Default::default()
                        })
                        .map(|x| x.config_dir())
                    } else {
                        Ok(PathBuf::from("/etc/nixos"))
                    }
                },
                |x| Ok(PathBuf::from(x)),
            )?;
        let home_flake = var_os("NH_HOME_FLAKE").or(flake).map_or_else(
            || {
                Xdg::new(AppStrategyArgs {
                    app_name: "home-manager".to_owned(),
                    ..Default::default()
                })
                .map(|x| x.config_dir())
            },
            |x| Ok(PathBuf::from(x)),
        )?;
        Ok(Self {
            os_flake,
            home_flake,
        })
    }
}
