use crate::*;
use clap_complete::generate;
use color_eyre::Result;
use tracing::instrument;

const NH_NAME: &str = env!("CARGO_PKG_NAME");

impl NHRunnable for interface::CompletionArgs {
    #[instrument(ret, level = "trace")]
    fn run(&self) -> Result<()> {
        let mut cmd = <NHParser as clap::CommandFactory>::command();
        generate(self.shell, &mut cmd, NH_NAME, &mut std::io::stdout());
        Ok(())
    }
}
