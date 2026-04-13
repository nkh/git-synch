**what does gsynch actually do under the hood, in Git plumbing terms, and how is that different from porcelain like `git checkout`?**

## 1. Mental model: gsynch as a controlled tree transplant

Conceptually, `gsynch` is:

1. Take a tree from a remote commit (the “source of truth”).
2. Transplant that tree into your local index and working tree.
3. Wrap the result in a clean, explicit commit.
4. Enforce safety rules before any destructive step.

Git already has the primitives for this; `gsynch` is basically a careful orchestration of:

- `git fetch`
- `git read-tree`
- `git checkout-index`
- `git write-tree`
- `git commit-tree`
- `git update-ref`

## 2. Fetching the upstream tree

First step: get the remote commit and its tree locally.

Roughly:

```bash
git fetch <url> <branch>:refs/gsynch/upstream
```

Now you have:

- A commit object: `C_upstream`
- A tree object: `T_upstream` (root tree of that commit)

`gsynch` doesn’t need the whole remote history for its logic; it mainly cares about:

- The commit ID (for audit)
- The tree ID (for mirroring)

## 3. Index as the staging mirror: git read-tree

The **index** is the heart of this. `git read-tree` is the plumbing command that makes the index look like a given tree.

Core idea:

```bash
git read-tree --reset <tree-ish>
# or with prefix/subdir:
git read-tree --reset --prefix=path/ <tree-ish>
```

Key properties:

- It **replaces the index** with the contents of the tree.
- It does **not** update the working tree unless combined with `-u`.
- It can be used with `--prefix` to read a tree into a subdirectory—this is how `gsynch --only <path>` can be implemented at the plumbing level.

In a gsynch‑style flow:

1. Build a temporary index that represents “what upstream should look like here”.
2. Compare that to the current index/working tree.
3. Decide what to overwrite, what to protect, and what to leave alone.

## 4. Updating the working tree: git checkout-index

Once the index is in the desired state, you need to make the working tree match it.

That’s what `git checkout-index` is for:

```bash
git checkout-index -a
# or selectively:
git checkout-index path/to/file
```

`git checkout-index`:

- Reads from the index.
- Writes files into the working tree.
- Is the plumbing counterpart of “the file checkout part” of `git checkout`.

In a gsynch‑style implementation:

- After `read-tree` has populated the index with the upstream tree (or subtree),
- `checkout-index` is used to materialize those entries into the working directory,
- But only for paths that are allowed by the safety rules (no overwrite of protected local changes unless explicitly overridden).

## 5. Safety logic: staged, modified, untracked

This is where `gsynch` stops being “just plumbing” and becomes opinionated.

To enforce safety, you need to classify local state:

- **Staged changes**: index differs from HEAD.
- **Modified changes**: working tree differs from index.
- **Untracked files**: present in working tree, not in index.

Plumbing helpers:

- `git ls-files -s` — show index entries.
- `git ls-files -m` — modified.
- `git ls-files -o --exclude-standard` — untracked.

`gsynch` can then:

- Build a set of “conflicting paths” where upstream wants to write something that would overwrite:
  - staged changes
  - modified files
  - untracked files
- Decide, based on flags:
  - Block entirely
  - Allow overwriting staged only
  - Allow overwriting modified only
  - Allow overwriting untracked only
  - Allow overwriting all (`--override-all`)

This is logic that porcelain like `git checkout` doesn’t give you in a structured, explicit way.

## 6. Forced‑push detection: comparing histories

To detect a forced push, you compare:

- The previously synced upstream commit (stored somewhere—e.g., a ref like `refs/gsynch/last-sync`).
- The new upstream commit after `git fetch`.

If the new commit is **not** a fast‑forward of the old one, upstream has been rewritten.

Plumbing:

- `git merge-base <old> <new>` — if merge base ≠ old, it’s not a fast‑forward.
- Or use `git rev-list` to check ancestry.

If a forced push is detected:

- `gsynch` refuses to proceed unless `--allow-forced-push` is set.
- This is a deliberate safety rail that plain `git fetch && git checkout` does not provide.

## 7. Building the new tree: git write-tree

Once the index represents the desired post‑sync state (after applying upstream, respecting overrides, and possibly limiting to a subtree), you need to turn that index into a tree object.

That’s `git write-tree`:

```bash
tree_id=$(git write-tree)
```

This:

- Reads the index.
- Writes a tree object into the object database.
- Returns the tree’s SHA‑1/SHA‑256.

This tree is the “snapshot” that your sync commit will point to.

## 8. Creating the sync commit: git commit-tree

Instead of using `git commit` (porcelain), you can create a commit directly with `git commit-tree`:

```bash
commit_id=$(echo "gsynch: sync from <branch> at <upstream-commit>" \
  | git commit-tree "$tree_id" -p <current-head>)
```

`git commit-tree`:

- Takes a tree ID.
- Takes one or more parent commits.
- Reads the commit message from stdin.
- Writes a commit object and returns its ID.

This gives you:

- A clean, explicit “sync commit”.
- A linear, auditable history of sync points.

## 9. Moving the branch: git update-ref

Finally, you need to move your current branch to point at the new sync commit.

That’s `git update-ref`:

```bash
git update-ref refs/heads/<branch> "$commit_id"
```

This:

- Updates the ref atomically.
- Does not touch the working tree by itself (that’s already been handled via index + checkout).

If you want to keep a record of the last upstream commit you synced from, you can also:

```bash
git update-ref refs/gsynch/last-sync <upstream-commit>
```

## 10. Removing the remote: read‑only mode

To enforce “one‑way” behavior, `gsynch` can remove the push‑capable remote:

```bash
git remote remove origin
```

This is not plumbing per se, but it’s a deliberate design choice:

- You keep the objects you fetched.
- You keep your sync history.
- You **cannot** accidentally push back to the source of truth.

## 11. Subtree sync: using prefixes

For `--only <path>`, you can lean on `git read-tree --prefix`:

```bash
git read-tree --reset --prefix=path/ <upstream-tree>
```

This:

- Keeps existing index entries.
- Reads the upstream tree under `path/`.
- Refuses to overwrite existing index entries at that prefix unless you explicitly clear them first.

A gsynch‑style flow might:

1. Clear the target subtree in the index (and working tree, respecting safety).
2. Use `read-tree --prefix` to inject the upstream subtree.
3. Use `checkout-index` to materialize it.

That’s how you get “sync only this directory” semantics that plain `git checkout` can’t do.

## 12. How this differs from git checkout internally

`git checkout` is a porcelain that internally uses many of the same plumbing commands:

- `git read-tree` (with merge/reset modes)
- `git checkout-index`
- `git update-ref` (to move HEAD/branch)

But:

- It’s optimized for **developer workflows** (branch switching, commit exploration).
- It does **not**:
  - enforce one‑way mirroring
  - detect forced pushes as a policy decision
  - treat untracked files as first‑class protected entities
  - provide fine‑grained override flags
  - create explicit “sync commits” with a stable pattern
  - support subtree‑only mirroring as a first‑class operation

`gsynch` is essentially:

> “Take the same plumbing, but wire it into a **strict, opinionated, deterministic** pipeline for mirroring upstream trees into a working directory, with safety rails.”

---

## TL;DR plumbing stack for gsynch

1. `git fetch` — get upstream commit/tree.
2. `git read-tree` — load upstream tree (or subtree) into the index.
3. `git ls-files` — classify local changes (staged/modified/untracked).
4. Safety logic — decide what’s allowed to be overwritten.
5. `git checkout-index` — update working tree from index.
6. `git write-tree` — snapshot the new index as a tree.
7. `git commit-tree` — create a sync commit.
8. `git update-ref` — move the branch to the sync commit.
9. `git remote remove` — enforce read‑only behavior.

```text

    ╭──────╮            ╭────────╮                   ╭───────────────╮                       ╭────────────╮
    │ User │            │ Gsynch │                   │ Upstream repo │                       │ Local repo │
    ╰──────╯            ╰────────╯                   ╰───────────────╯                       ╰────────────╯
        │                    │                               │                                       │
        │    run gsynch      │                               │                                       │
        │───────────────────⮞│                               │                                       │
        │                    │   git fetch <url> <branch>    │                                       │
        │                    │──────────────────────────────⮞│                                       │
        │                    │    upstream commit + tree     │                                       │
        │                    │⮜─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌│                                       │
        │                    │                    git ls-files -s (index state)                      │
        │                    │──────────────────────────────────────────────────────────────────────⮞│
        │                    │                            staged entries                             │
        │                    │⮜─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌│
        │                    │                  git ls-files -m (modified files)                     │
        │                    │──────────────────────────────────────────────────────────────────────⮞│
        │                    │                           modified entries                            │
        │                    │⮜─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌│
        │                    │        git ls-files -o --exclude-standard (untracked files)           │
        │                    │──────────────────────────────────────────────────────────────────────⮞│
        │                    │                          untracked entries                            │
        │                    │⮜─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌│
        │                    │apply safety rules (block or allow) -+                                 │
        │                    <-------------------------------------+                                 │
        │                    │   git read-tree --reset <upstream-tree> (or --prefix for subtree)     │
        │                    │──────────────────────────────────────────────────────────────────────⮞│
        │                    │                    index updated to upstream tree                     │
        │                    │⮜─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌│
        │                    │     git checkout-index -a (materialize index into working tree)       │
        │                    │──────────────────────────────────────────────────────────────────────⮞│
        │                    │                         working tree updated                          │
        │                    │⮜─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌│
        │                    │                            git write-tree                             │
        │                    │──────────────────────────────────────────────────────────────────────⮞│
        │                    │                            <new-tree-id>                              │
        │                    │⮜─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌│
        │                    │   git commit-tree <new-tree-id> -p <old-head> "gsynch: sync ..."      │
        │                    │──────────────────────────────────────────────────────────────────────⮞│
        │                    │                           <new-commit-id>                             │
        │                    │⮜─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌─╌│
        │                    │          git update-ref refs/heads/<branch> <new-commit-id>           │
        │                    │──────────────────────────────────────────────────────────────────────⮞│
        │                    │                       git remote remove origin                        │
        │                    │──────────────────────────────────────────────────────────────────────⮞│
        │   sync complete    │                               │                                       │
        │⮜───────────────────│                               │                                       │
        │                    │                               │                                       │

```

