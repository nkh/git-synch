
# gsynch

`gsynch` is a deterministic, one‑way synchronization tool that mirrors files from a remote Git repository into your current working directory. It is designed for reproducible workflows, vendor code imports, template mirroring, and controlled updates where the remote repository acts as the source of truth.

Unlike ad‑hoc copying or patching, `gsynch` uses Git’s own tree‑restore mechanisms to ensure safe, reversible, and traceable updates.

---

## Features

- **One‑way synchronization** from a remote repo/branch into the current directory  
- **Subdirectory sync** with `--only <path>`  
- **Safety checks** for dirty trees and untracked file collisions  
- **`--no-commit` mode** for staged‑only updates  
- **`--dry-run` mode** to preview all changes  
- **Tag mirroring** for upstream tags pointing at the synced commit  
- **Automatic repo initialization** (with initial commit) if the directory is not a Git repo  
- **ANSI‑colored output** with a consistent `gsynch:` prefix  
- **Force mode** to override safety checks  
- **Zero dependencies** beyond Git itself  

### Design Rationale

## Automatic Git Initialization
A baseline commit is required for diffs, restores, and reverts. Without it,
synchronization would overwrite files blindly.

## Dirty‑Tree Protection
Uncommitted changes would be destroyed by a sync. Blocking prevents accidental
data loss.

## Untracked‑File Collision Detection
Untracked files are invisible to Git. If they collide with incoming files,
they would be overwritten silently. gsynch blocks this unless --force is used.

## Subdirectory Sync
Many workflows only need a subtree (e.g., vendor code). This avoids touching
unrelated files.

## Dry Run
Synchronization is destructive. A preview mode is essential for safe use.

## No Commit Mode
Allows inspection, batching, or integration into larger workflows.

## Tag Mirroring
Ensures the local sync corresponds exactly to a known upstream state.

## Prefixed, Colored Output
Makes gsynch output easy to distinguish from Git output, especially in CI logs.

---

## Local Installation

```bash
./gsynch/install.sh
```

## Remote installation

```bash
curl -L https://raw.githubusercontent.com/nkh/git-synch/refs/heads/main/install_remote.sh | bash
```


