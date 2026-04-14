# gsynch

`gsynch` is a deterministic, one‑way synchronization tool that mirrors files from a remote Git repository into your current working directory. It is designed for developers who want a safe, predictable way to import vendor code, templates, boilerplate, or shared assets — without risking accidental overwrites or merges.

Unlike `git pull`, `gsynch` never merges, never rebases, and never rewrites your history. It performs a controlled, auditable update from a remote source of truth.

![Sequence](https://github.com/nkh/git-synch/blob/main/sequence.png)

## Why gsynch?

Many workflows need a “pull‑from‑upstream‑but‑never‑push‑back” mechanism:

- Importing vendor libraries into your project  
- Keeping template directories up to date  
- Mirroring a shared configuration repo  
- Updating generated assets  
- Syncing boilerplate across multiple projects  

`gsynch` solves this cleanly:

- No merges  
- No rebases  
- No accidental pushes  
- No silent overwrites  
- No surprises  

You get a deterministic, reproducible update every time.

---

## Key Features

### One‑way synchronization  
Your working directory is updated to match a remote repo/branch.  
Your local changes are protected unless you explicitly override them.

### Fine‑grained safety controls  
`gsynch` detects three types of local changes:

- Staged (index)  
- Modified (working tree)  
- Untracked (new files)  

By default, any of these will block the sync if they would be overwritten.

You can selectively override:

- `--override-staged`  
- `--override-modified`  
- `--override-untracked`  
- `--override-all`  

### Forced‑push protection  
If the upstream branch was force‑pushed, `gsynch` will stop unless you explicitly allow it:

```
--allow-forced-push
```

### Subdirectory sync  
Only update a specific subtree:

```
gsynch --only path/to/subdir
```

### Dry‑run mode  
Preview exactly what would change:

```
gsynch --dry-run
```

### No‑commit mode  
Stage updates without committing:

```
gsynch --no-commit
```

### Automatic repo initialization  
If your directory is not a Git repo, `gsynch` will initialize one and create a baseline commit.

### Empty directory bootstrap  
If the directory is empty, `gsynch` performs:

```
git clone --branch <branch> <url> .
git remote remove origin
```

This gives you a clean working tree without a push‑capable `origin`.

---

## Installation

### Local installation

```
./gsynch/install.sh
```

### Remote installation

```
curl -L https://raw.githubusercontent.com/nkh/git-synch/refs/heads/main/install_remote.sh | bash
```

---

## Usage

### Basic sync

```
gsynch --url https://github.com/example/vendor --branch main
```

This will:

1. Fetch the upstream branch  
2. Compare it to your current state  
3. Restore changed files  
4. Commit the update  

If nothing changed:

```
gsynch: Already up to date. No changes.
```

---

## Examples

### Example 1 — Safe update with no local changes

```
gsynch --url https://github.com/example/templates --branch main
```

Output:

```
gsynch: Syncing from example_templates/main
gsynch: No untracked files will be overwritten.
gsynch: Already up to date. No changes.
```

---

### Example 2 — Modified file blocks the sync

```
echo "local edit" > config.yml
gsynch --url https://github.com/example/config --branch main
```

Output:

```
gsynch: ERROR: Working tree or index has uncommitted changes.
Use --override-modified or --override-all to override.
```

---

### Example 3 — Overwrite modified files explicitly

```
gsynch --url https://github.com/example/config --branch main --override-modified
```

---

### Example 4 — Sync only a subdirectory

```
gsynch --url https://github.com/example/vendor --branch main --only src/lib
```

---

### Example 5 — Continue after a forced push

```
gsynch --url https://github.com/example/templates --branch main --allow-forced-push
```

---

## How It Works (Technical Overview)

1. Ensures required options (`--url`, `--branch`) are set  
2. Detects empty directory → performs a clone  
3. Ensures directory is a Git repo → initializes if needed  
4. Fetches upstream  
5. Detects forced push  
6. Classifies local changes into staged / modified / untracked  
7. Applies override rules  
8. Restores upstream tree (skipping protected files)  
9. Creates a commit (unless `--no-commit`)  
10. Mirrors upstream tags  

The result is a deterministic, reproducible sync.

---

## When NOT to use gsynch

- When you want to merge your own changes with upstream  
- When you want to push changes back to the remote  
- When you need bidirectional sync  
- When you want Git to resolve conflicts automatically  

`gsynch` is intentionally one‑way and conflict‑free.

---

## License

Artistic license 2.0 or GPL-3.0 (your choice)

