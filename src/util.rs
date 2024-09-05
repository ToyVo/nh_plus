extern crate semver;

use color_eyre::{eyre, Result};
use semver::Version;
use tempfile::TempDir;
use tracing::debug;
use which::which;

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::str;
use subprocess::{Exec, Redirection};

use crate::interface::NHParser;

/// Compares two semantic versions and returns their order.
///
/// This function takes two version strings, parses them into `semver::Version` objects, and compares them.
/// It returns an `Ordering` indicating whether the current version is less than, equal to, or
/// greater than the target version.
///
/// # Arguments
///
/// * `current` - A string slice representing the current version.
/// * `target` - A string slice representing the target version to compare against.
///
/// # Returns
///
/// * `Result<std::cmp::Ordering>` - The comparison result.
pub fn compare_semver(current: &str, target: &str) -> Result<std::cmp::Ordering> {
    let current = Version::parse(current)?;
    let target = Version::parse(target)?;

    Ok(current.cmp(&target))
}

/// Retrieves the installed Nix version as a string.
///
/// This function executes the `nix --version` command, parses the output to extract the version string,
/// and returns it. If the version string cannot be found or parsed, it returns an error.
///
/// # Returns
///
/// * `Result<String>` - The Nix version string or an error if the version cannot be retrieved.
pub fn get_nix_version() -> Result<String> {
    let output = Command::new("nix").arg("--version").output()?;

    let output_str = str::from_utf8(&output.stdout)?;
    let version_str = output_str
        .lines()
        .next()
        .ok_or_else(|| eyre::eyre!("No version string found"))?;

    // Extract the version substring using a regular expression
    let re = regex::Regex::new(r"\d+\.\d+\.\d+")?;
    if let Some(captures) = re.captures(version_str) {
        let version = captures
            .get(0)
            .ok_or_else(|| eyre::eyre!("No version match found"))?
            .as_str();
        return Ok(version.to_string());
    }

    Err(eyre::eyre!("Failed to extract version"))
}

pub trait MaybeTempPath: std::fmt::Debug {
    fn get_path(&self) -> &Path;
}

impl MaybeTempPath for PathBuf {
    fn get_path(&self) -> &Path {
        self.as_ref()
    }
}

impl MaybeTempPath for (PathBuf, TempDir) {
    fn get_path(&self) -> &Path {
        self.0.as_ref()
    }
}

/// Gets a path to a previlege elevation program based on what is available in the system
/// or from the command line arguments.
///
/// First this function checks for a program specified by the command line arguments,
/// checks if it exists in the `PATH` with the `which` crate and returns a Ok result
/// with the OsString of the path to the binary or a Err result if not.
///
/// If no command line arguments were found, this funtion checks for the existence of
/// common privilege elevation program names in the `PATH` using the `which` crate and
/// returns a Ok result with the `OsString` of the path to the binary. In the case none
/// of the checked programs are found a Err result is returned.
///
/// The search is done in this order:
///
/// 1. `doas`
/// 1. `sudo`
/// 1. `run0`
/// 1. `pkexec`
///
/// The logic for choosing this order is that a person with doas installed is more likely
/// to be using it as their main privilege elevation program.
///
/// # Returns
///
/// * `Result<OsString>` - The absolute path to the privilege elevation program binary or an error if a
/// program can't be found.
pub fn get_elevation_program() -> Result<(OsString, Vec<OsString>)> {
    let args = <NHParser as clap::Parser>::parse();
    if let Some(path) = args.elevation_program.map(|path| which(path)) {
        debug!(
            ?path,
            "privilege elevation path specified via command line argument"
        );
        return Ok((path?.into_os_string(), vec![]));
    }

    const STRATEGIES: [&str; 4] = ["doas", "sudo", "run0", "pkexec"];

    for strategy in STRATEGIES {
        if let Ok(path) = which(strategy) {
            debug!(?path, "{strategy} path found");
            let mut args = vec![];
            if strategy == "sudo" {
                // Check for if sudo has the preserve-env flag
                let preserve_env = Exec::cmd(path.clone().into_os_string())
                    .args([OsString::from("--help")].as_ref())
                    .stderr(Redirection::None)
                    .stdout(Redirection::Pipe)
                    .capture()?
                    .stdout_str()
                    .contains("--preserve-env");

                args = if preserve_env {
                    vec![
                        OsString::from("-H"),
                        OsString::from("--preserve-env=PATH"),
                        OsString::from("env"),
                    ]
                } else {
                    vec![OsString::from("-H")]
                };
            }
            return Ok((path.into_os_string(), args));
        }
    }

    Err(eyre::eyre!("No elevation strategy found"))
}

#[cfg(not(target_os = "macos"))]
pub fn hostname() -> eyre::Result<OsString> {
    hostname::get().context("Failed to get hostname")
}

#[cfg(target_os = "macos")]
pub fn hostname() -> eyre::Result<OsString> {
    use system_configuration::{
        core_foundation::{base::TCFType, string::CFString},
        sys::dynamic_store_copy_specific::SCDynamicStoreCopyLocalHostName,
    };

    let ptr = unsafe { SCDynamicStoreCopyLocalHostName(std::ptr::null()) };
    if ptr.is_null() {
        return Err(eyre::eyre!("Failed to get hostname"));
    }
    let name = unsafe { CFString::wrap_under_get_rule(ptr) };

    Ok(name.to_string().into())
}
