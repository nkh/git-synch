# gsynch — Deterministic One‑Way Synchronization from a Remote Git Repository

`gsynch` synchronizes the contents of a remote Git repository into the current working directory using Git’s tree‑restore mechanisms. It is designed for **deterministic**, **reproducible**, **one‑way** workflows where the remote repository is the authoritative source of truth.

Local changes are protected by default and require explicit override flags to be overwritten.

---

# Features

- Deterministic one‑way sync from a remote Git repository  
- Protects local changes unless explicitly overridden  
- Detects forced pushes and aborts unless allowed  
- Supports syncing only a subdirectory (`--only`)  
- Dry‑run mode for safe previews  
- Optional commit suppression (`--no-commit`)  
- **Preserve local files deleted upstream (`--no-local-delete`)**  
- **Debug mode for deep inspection (`--debug`)**  
- Automatic initialization of non‑git directories  
- Safe bootstrap of empty directories  
- Mirrors tags pointing at the upstream commit  
- Clean, reproducible commit messages  

---

# Installation

```
sudo install -m 755 gsynch /usr/local/bin/
```

Or run directly from the repo:

```
./gsynch --url [https://example.com/repo.git](https://example.com/repo.git)
```

---

# Usage

```
gsynch --url <url> [options]
```

---

# Full CLI Option List

### Core Options

| Option              | Description                                                 |
| --------            | -------------                                               |
| `--url <url>`       | Remote repository URL (required unless `GSYNCH_URL` is set) |
| `--branch <branch>` | Branch to sync from (default: `main`)                       |
| `--only <path>`     | Sync only a subdirectory                                    |
| `--dry-run`         | Show what would happen without modifying anything           |
| `--no-commit`       | Stage changes but do not commit                             |
| `--debug`           | Show detailed debugging information                         |
| `-h`, `--help`      | Show help                                                   |

### Override Options

| Option                 | Description                              |
| --------               | -------------                            |
| `--override-staged`    | Allow overwriting staged files           |
| `--override-modified`  | Allow overwriting modified tracked files |
| `--override-untracked` | Allow overwriting untracked files        |
| `--override-all`       | Enable all overrides                     |

### Deletion & Forced Push Handling

| Option                | Description                                   |
| --------              | -------------                                 |
| `--no-local-delete`   | Preserve local files even if deleted upstream |
| `--allow-forced-push` | Continue even if upstream was force‑pushed    |

---

# Environment Variables

| Variable        | Meaning              |
| ----------      | ---------            |
| `GSYNCH_URL`    | Default upstream URL |
| `GSYNCH_BRANCH` | Default branch name  |

These act as defaults and can be overridden by CLI options.

---

# Behavior

## Empty Directory Bootstrap

If the directory is empty:

```
git clone --branch BRANCH URL .
git remote remove origin
```

This prevents accidental pushes.

## Non‑Git Directory Initialization

If the directory is not a Git repo:

```
git init
git add .
git commit -m "Initial import of existing working directory"
```

This creates a deterministic baseline.

## Local Change Classification

`gsynch` classifies local files as:

- **Staged**  
- **Modified**  
- **Untracked**

Without overrides, any of these will block synchronization.

## Override Semantics

If any override flag is provided:

- Classes with overrides are overwritten  
- Classes without overrides are preserved  

This allows fine‑grained control.

---

# Upstream Deletion Behavior

By default, if the upstream repository deletes a file, `gsynch` deletes it locally.

To preserve local files deleted upstream:

```
gsynch --url <url> --no-local-delete
```

This applies **only** to upstream deletions.  
It does **not** protect:

- modified files  
- staged files  
- untracked files  

### Example: Preventing deletion of local config files

```
gsynch --url [https://example.com/repo.git](https://example.com/repo.git) --no-local-delete
```

---

# Subdirectory Synchronization

Sync only a subtree:

```
gsynch --url <url> --only path/to/subdir
```

---

# Forced Push Detection

If the upstream branch was force‑pushed, `gsynch` aborts unless:

```
gsynch --allow-forced-push
```

---

# Debug Mode

Enable detailed debugging:

```
gsynch --debug --url <url>
```

This prints:

- Local commit graph  
- Remote commit graph  
- Merge‑base diagnostics  
- SHA comparisons  

Useful for diagnosing unexpected diffs or forced‑push behavior.

---

# Tag Mirroring

After synchronization, `gsynch` mirrors any tags pointing at the upstream commit:

```
git tag -f <tag> <sha>
```

Only tags pointing at the upstream commit are mirrored.

---

# Commit Message Format

Automatic commits use:

```
Sync from <remote>/<branch> (<sha>): <subject>
```

This makes sync history easy to audit.

---

# Remote Naming Scheme

`gsynch` does **not** use `origin`.

Instead, it sanitizes the URL:

- Non‑alphanumeric characters → `_`
- Example:  
  `https://github.com/foo/bar.git` → `https___github_com_foo_bar_git`

This allows multiple upstreams to coexist safely.

---

# Exit Codes

| Code   | Meaning                                      |
| ------ | ---------                                    |
| `0`    | Sync completed successfully or nothing to do |
| `>0`   | Error, conflict, or unsafe local state       |

---

# Examples

### Basic sync

```
gsynch --url [https://example.com/repo.git](https://example.com/repo.git)
```

### Sync only a subdirectory

```
gsynch --url [https://example.com/repo.git](https://example.com/repo.git) --only src/
```

### Allow overwriting modified files

```
gsynch --url <url> --override-modified
```

### Preserve local files deleted upstream

```
gsynch --url <url> --no-local-delete
```

### Debug mode

```
gsynch --url <url> --debug
```

---

# When *Not* to Use gsynch

- When you need two‑way sync  
- When you want to push changes upstream  
- When you want Git to manage merges automatically  

`gsynch` is intentionally **one‑way** and **destructive** when overrides are used.

---

# License

## License

Artistic license 2.0 or GPL-3.0 (your choice)

