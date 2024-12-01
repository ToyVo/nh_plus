use tracing::warn;

use crate::commands::Command;
use crate::installable::Installable;
use crate::Result;

pub fn update(installable: &Installable, input: Option<String>) -> Result<()> {
    match installable {
        Installable::Flake { reference, .. } => {
            let mut cmd = Command::new("nix").args(["flake", "update"]);

            if let Some(i) = input {
                cmd = cmd.arg(&i).message(format!("Updating flake input {}", i));
            } else {
                cmd = cmd.message("Updating all flake inputs");
            }

            cmd.arg("--flake").arg(reference).run()?;
        }
        _ => {
            warn!(
                "Only flake installables can be updated, {} is not supported",
                installable.str_kind()
            );
        }
    }

    Ok(())
}

pub fn pull(installable: &Installable) -> Result<()> {
    match installable {
        Installable::Flake { reference, .. } => {
            Command::new("git")
                .args(["-C", reference, "pull"])
                .message("Pulling flake")
                .run()?;
        }
        _ => {
            warn!(
                "Only flake installables can be updated, {} is not supported",
                installable.str_kind()
            );
        }
    }

    Ok(())
}

pub fn check_for_conflicts(installable: &Installable) -> Result<()> {
    if let Installable::Flake { reference, .. } = installable {
        let status = Command::new("git")
            .args(["-C", reference, "diff", "--name-only", "--diff-filter=U"])
            .message("Checking for conflicts")
            .run_capture()?;

        if let Some(conflict) = status {
            if conflict == "flake.lock\n".to_string() {
                Command::new("git")
                    .args(["-C", reference, "reset", "flake.lock"])
                    .message("Resetting flake.lock")
                    .run()?;
                Command::new("git")
                    .args(["-C", reference, "checkout", "flake.lock"])
                    .message("Checking out flake.lock")
                    .run()?;
            } else if conflict != "" {
                panic!("Conflicts detected that were more than just flake.lock");
            }
        }
    }

    Ok(())
}
