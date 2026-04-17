#!/usr/bin/env bash
set -euo pipefail

GSYNCH_BIN="${GSYNCH_BIN:-$PWD/gsynch}"

fail() { echo -e "FAIL: $*" >&2; exit 1; }
ok()   { echo -e "OK: $*"; }

tmpdir() {
    d=$(mktemp -d)
    echo "$d"
}

# Create an upstream repo with one commit
make_upstream() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main || git -C "$dir" init -q
    echo "hello" > "$dir/file.txt"
    git -C "$dir" add file.txt
    git -C "$dir" commit -q -m "initial"
}

test_missing_config_fails() {
    local wd
    wd=$(tmpdir)
    cd "$wd"
    if "$GSYNCH_BIN" &>err.log; then
        fail "gsynch should fail without URL/BRANCH"
    fi
    grep -q "URL is not set" err.log || fail "missing URL error not shown"
    ok "missing config fails as expected"
}

test_basic_sync() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"
    touch abc

    GSYNCH_URL="$upstream" GSYNCH_BRANCH="main" "$GSYNCH_BIN" &>/dev/null

    [ -f file.txt ] || fail "file.txt not synced"
    grep -q "hello" file.txt || fail "file.txt content mismatch"
    ok "basic sync works"
}

test_dry_run_no_changes() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"
    touch abc

    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null
    "$GSYNCH_BIN" --url "$upstream" --branch main --dry-run >out.log

    grep -q "Not modifying working tree" out.log || fail "dry-run up-to-date message missing"
    ok "dry-run on up-to-date repo works"
}

test_untracked_collision_blocks() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"
    touch abc
    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null

    git rm -f file.txt >/dev/null
    git commit -q -m "remove file.txt"
    echo "local" > file.txt  # untracked overwrite candidate

    if "$GSYNCH_BIN" --url "$upstream" --branch main &>err.log; then
        fail "gsynch should fail on untracked collision"
    fi
    grep -q "untracked files would be overwritten" err.log || fail "collision message missing"

    ok "untracked collision is blocked"
}

test_uncommitted_blocks() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"

    touch abc
    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null

    echo "changed" > file.txt
    git add file.txt >/dev/null

    if "$GSYNCH_BIN" --url "$upstream" --branch main >err.log ; then
        fail "gsynch should fail on uncommitted files"
    fi

    grep -q "has uncommitted changes" err.log || fail "uncommitted message missing"
    ok "uncommitted is blocked"
}

test_modified_blocks() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"

    touch abc
    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null

    echo "changed" > file.txt  # modified but not staged

    if "$GSYNCH_BIN" --url "$upstream" --branch main >err.log ; then
        fail "gsynch should fail on modified files"
    fi

    grep -q "has uncommitted changes" err.log || fail "modified message missing"
    ok "modified is blocked"
}

test_override_staged_allows_overwrite() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"
    touch abc

    "$GSYNCH_BIN" --url "$upstream" --branch main --no-local-delete &>/dev/null

    echo "changed" > file.txt
    git add file.txt >/dev/null

    "$GSYNCH_BIN" --url "$upstream" --branch main --override-staged &>/dev/null
    "$GSYNCH_BIN" --url "$upstream" --branch main --override-staged &>/dev/null

    grep -q "hello" file.txt || fail "override-staged did not overwrite file.txt"
    ok "override-staged overwrites staged changes"
}

test_override_modified_allows_overwrite() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"
    touch abc
    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null

    echo "changed" > file.txt  # modified but not staged

    "$GSYNCH_BIN" --url "$upstream" --branch main --override-modified &>/dev/null

    grep -q "hello" file.txt || fail "override-modified did not overwrite file.txt"
    ok "override-modified overwrites modified tracked files"
}

test_override_untracked_allows_overwrite() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"
    touch abc
    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null

    git rm -f file.txt >/dev/null
    git commit -q -m "remove file.txt"
    echo "local" > file.txt  # untracked overwrite candidate

    "$GSYNCH_BIN" --url "$upstream" --branch main --override-untracked &>/dev/null

    grep -q "hello" file.txt || fail "override-untracked did not overwrite file.txt"
    ok "override-untracked overwrites colliding untracked files"
}

test_override_all_allows_overwrite() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"
    touch abc
    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null

    echo "local" > file.txt
    echo "extra" > extra.txt

    "$GSYNCH_BIN" --url "$upstream" --branch main --override-all &>/dev/null

    grep -q "hello" file.txt || fail "override-all did not overwrite file.txt"
    [ -f extra.txt ] || fail "extra.txt should remain (not in upstream)"
    ok "override-all overwrites tracked paths and keeps unrelated files"
}

test_forced_push_blocks_without_flag() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    # echo remote is at: $upstream

    # First sync
    wd=$(tmpdir)
    cd "$wd"
    touch abc # should not be needed as gsynch works with empty worktree

    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null

    # Force-push upstream
    echo "hello2" > "$upstream/file.txt"
    git -C "$upstream" add file.txt
    git -C "$upstream" commit -q -m "remote update"

    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null

    git -C "$upstream" reset --hard HEAD~1 >/dev/null
    touch "$upstream/remote_new_file"
    git -C "$upstream" add remote_new_file
    git -C "$upstream" commit -q -m "remote new file"

    if "$GSYNCH_BIN" --url "$upstream" --branch main &> err.log; then
        fail "gsynch should fail on forced push without allow flag"

    fi
    grep -q "Aborting due to forced push" err.log || fail "forced push abort message missing"

    ok "forced push blocks without flag"
}

test_forced_push_allows_with_flag() {
    local upstream wd
    upstream=$(tmpdir)
    make_upstream "$upstream"

    wd=$(tmpdir)
    cd "$wd"
    touch abc
    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null

    echo "hello2" > "$upstream/file.txt"
    git -C "$upstream" add file.txt
    git -C "$upstream" commit -q -m "force update"
    git -C "$upstream" reset --hard HEAD~1 >/dev/null
    git -C "$upstream" cherry-pick HEAD@{1} >/dev/null 2>&1 || true

    "$GSYNCH_BIN" --url "$upstream" --branch main --allow-forced-push &>/dev/null

    grep -q "hello2" file.txt || fail "forced push with flag did not update file.txt"
    ok "forced push allowed with flag"
}

test_large_repo_performance() {
    local upstream wd
    upstream=$(tmpdir)
    mkdir -p "$upstream"
    git -C "$upstream" init -q -b main || git -C "$upstream" init -q

    local i
    for i in $(seq 1 2000); do
        echo "file $i" > "$upstream/file_$i.txt"
    done
    git -C "$upstream" add .
    git -C "$upstream" commit -q -m "large repo"

    wd=$(tmpdir)
    cd "$wd"
    touch marker

    local start=$SECONDS
    "$GSYNCH_BIN" --url "$upstream" --branch main &>/dev/null
    local elapsed=$((SECONDS - start))

    [ -f file_1.txt ] || fail "large repo sync missing file_1.txt"
    [ -f file_2000.txt ] || fail "large repo sync missing file_2000.txt"

    echo "Large repo sync elapsed: ${elapsed}s"
    ok "large repo performance test completed"
}

main() {
    test_missing_config_fails
    test_basic_sync
    test_dry_run_no_changes
    test_untracked_collision_blocks
    test_uncommitted_blocks
    test_modified_blocks
    test_override_staged_allows_overwrite
    test_override_modified_allows_overwrite
    test_override_untracked_allows_overwrite
    test_override_all_allows_overwrite
    test_forced_push_blocks_without_flag
    test_forced_push_allows_with_flag
    # test_large_repo_performance
    echo "All tests passed."
}

main "$@"
