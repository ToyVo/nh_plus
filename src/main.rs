mod clean;
mod commands;
mod completion;
mod config;
mod home;
mod interface;
mod json;
mod logging;
mod nixos;
mod repl;
mod search;
mod util;

use crate::interface::NHParser;
use crate::interface::NHRunnable;
use crate::util::get_elevation_program;
use color_eyre::Result;
use std::ffi::OsString;
use tracing::debug;

const NH_VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() -> Result<()> {
    let args = <NHParser as clap::Parser>::parse();
    crate::logging::setup_logging(args.verbose)?;
    tracing::debug!(?args);
    tracing::debug!(%NH_VERSION);
    if args.verbose {
        let path = std::env::var("PATH").unwrap_or_default();
        tracing::debug!(?path);
    }

    args.command.run()
}

fn self_elevate() -> ! {
    use std::os::unix::process::CommandExt;

    let (program, mut additional_args) = get_elevation_program().unwrap();
    for arg in std::env::args() {
        additional_args.push(OsString::from(arg));
    }
    let mut cmd = std::process::Command::new(program);
    cmd.args(additional_args);
    debug!("{:?}", cmd);
    let err = cmd.exec();
    panic!("{}", err);
}
