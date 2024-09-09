use crate::*;
use clap_complete::generate;
use color_eyre::Result;
use tracing::instrument;

impl NHRunnable for interface::CompletionArgs {
    #[instrument(ret, level = "trace")]
    fn run(&self) -> Result<()> {
        let mut cmd = <NHParser as clap::CommandFactory>::command();
        generate(
            self.shell,
            &mut cmd,
            std::path::Path::new(&std::env::args_os().next().expect("current executable"))
                .file_name()
                .expect("executable filename")
                .to_string_lossy(),
            &mut std::io::stdout(),
        );
        Ok(())
    }
}
