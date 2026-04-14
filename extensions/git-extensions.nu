# -----------------------------------------
# private functions
# -----------------------------------------

def run-and-get-output-obj [command: closure]: nothing -> record {
  let output = do $command | complete;
  if $output.exit_code != 0 {
    error make {
      msg: $output.stderr
      label: {
        text: $output.stderr,
        span: (metadata $command).span
      }
    };
  }
  $output
}

def run-and-get-text [command: closure] {
  let output = run-and-get-output-obj $command;
  $output.stdout | str trim
}

def run-and-get-lines [command: closure] {
  let output = run-and-get-output-obj $command;
  $output.stdout | split row "\n" | where {|it| $it != "" }
}

def sort-branches [lines: list<string>] {
  let others = $lines |
      where {|b| not ($b | str starts-with "*") } |
      each {|b| ($b | str trim) };
  let with_star = $lines | where {|b| ($b | str starts-with "*") };
  let current = if (($with_star | length) > 0) {
    let after_star = $with_star.0 | str substring 1.. | str trim;
    if ($after_star | str starts-with "(HEAD") { "HEAD" } else { $after_star }
  } else { "HEAD" };
  { current: $current, others: $others }
}

def get-current-commit-info [] {
  let sha1 = run-and-get-text { git rev-parse HEAD };
  let lines = run-and-get-lines { git branch -a --contains };
  let branches = sort-branches $lines;
  mut rec = { current-commit: $sha1 };
  if ($branches.current != null) {
    $rec.current-branch = $branches.current;
  }
  if (($branches.others | length) > 0) {
    $rec.branches-containing = $branches.others;
  }
  $rec
}

def leave_branch [] {
  let sha1 = run-and-get-text { git rev-parse HEAD };
  run-and-get-text { git checkout -q $sha1 };
}

def delete_branch [name: string] {
  run-and-get-text { git branch -D $name };
  { branch-name: $name }
}

def rebase-in-order [target_commit: string, rebased_branch: string] {
  let rebased_branch = if ($rebased_branch == "" or $rebased_branch == "HEAD") {
    run-and-get-text { git rev-parse --abbrev-ref HEAD };
  } else {
    $rebased_branch
  };
  if ($rebased_branch == "HEAD") {
    error make {
      msg: "Not on a branch",
      label: {
        text: "Not on a branch",
        span: (metadata $rebased_branch).span
      }
    };
  }
  let target_sha1 = run-and-get-text { git rev-parse $target_commit };
  let branch_sha1 = run-and-get-text { git rev-parse $rebased_branch };
  let toResult = { |action, common|
    return {
      action-realised: $action,
      target-commit: { name: $target_commit, sha1: $target_sha1 },
      rebased-branch: { name: $rebased_branch, sha1: $branch_sha1 },
      common-base: $common,
    };
  };
  if ($branch_sha1 == $target_sha1) {
    return (do $toResult "nothing to do" $target_sha1);
  }
  let common_sha1 = run-and-get-text { git merge-base $target_sha1 $branch_sha1 };
  if ($common_sha1 == $target_sha1) {
    return (do $toResult "nothing to do" $common_sha1);
  } else if ($common_sha1 == $branch_sha1) {
    return (do $toResult "suspicious attempt" $common_sha1);
  }
  let divergence = run-and-get-text { git log --min-parents=2 $"($common_sha1)..($branch_sha1)" };
  if ($divergence == "") {
    run-and-get-text { git rebase --onto $target_sha1 $common_sha1 $rebased_branch };
    do $toResult "rebased" $common_sha1
  } else {
    do $toResult "non linear history" $common_sha1
  }
}

# -----------------------------------------
# graph: navigate
# -----------------------------------------

# Checkout branch origin/main
export def 'gt cmain' [] {
  run-and-get-text { git switch --detach -q origin/main };
  get-current-commit-info
}

# Checkout branch origin/develop
export def 'gt cdev' []  {
  run-and-get-text { git switch --detach -q origin/develop };
  get-current-commit-info
}

# Checkout branch origin/master
export def 'gt cmast' []  {
  run-and-get-text { git switch --detach -q origin/master };
  get-current-commit-info
}

# Checkout branch origin/release/v2
export def 'gt cv2' []  {
  run-and-get-text { git switch --detach -q origin/release/v2 };
  get-current-commit-info
}

# Checkout a branch
export def 'gt co' [branch_name: string]  {
  run-and-get-text { git switch $branch_name };
  get-current-commit-info
}

# Checkout a detached branch (=without actually pointing to the branch)
export def 'gt cod' [commit: string]  {
  run-and-get-text { git checkout --detach $commit };
  get-current-commit-info
}

# -----------------------------------------
# branches: list / create / move / delete
# -----------------------------------------

# List local branches
export def 'gt br' [] {
  let lines = run-and-get-lines { git branch };
  let branches = sort-branches $lines;
  mut rec = {};
  if ($branches.current != null) {
    $rec.current = $branches.current;
  }
  if (($branches.others | length) > 0) {
    $rec.others = $branches.others;
  }
  $rec
}

# Create a new branch
export def 'gt nbr' [name: string] {
  run-and-get-text { git checkout -b $name };
  get-current-commit-info
}

# Move a branch to a specific commit
export def 'gt mbr' [name: string, dest: string = ""] {
  if ($dest == "") {
    run-and-get-text { git branch -f $name };
  } else {
    run-and-get-text { git branch -f $name $dest };
  }
  get-current-commit-info
}

# Move a branch to a specific commit and checkout
export def 'gt mbr-co' [name: string, dest: string = ""] {
  if ($dest == "") {
    run-and-get-text { git branch -f $name };
  } else {
    run-and-get-text { git branch -f $name $dest };
  }
  run-and-get-text { git checkout $name };
  get-current-commit-info
}

# Delete a branch
export def 'gt dbr' [name: string = ""] {
  let current = run-and-get-text { git rev-parse --abbrev-ref HEAD };
  if ($name != "") {
    if ($current == $name) { leave_branch }
    delete_branch $name
  } else if ($current == "HEAD") {
    error make {
      msg: "Not on a branch"
      label: {
        text: "Not on a branch",
        span: (metadata $name).span
      }
    }
  } else {
    leave_branch;
    delete_branch $current
  }
}

# Rename a branch
export def 'gt rbr' [name1: string, name2: string = ""] {
  if ($name2 == "") {
    run-and-get-text { git branch -m $name1 };
    { old-name: "HEAD", new-name: $name1 }
  } else {
    run-and-get-text { git branch -m $name1 $name2 };
    { old-name: $name1, new-name: $name2 }
  }
}

# -----------------------------------------
# branches: rebase
# -----------------------------------------

# Rebase a branch on origin/main
export def 'gt on-main' [rebased_branch: string = ""] {
  rebase-in-order "origin/main" $rebased_branch
}

# Rebase a branch on origin/develop
export def 'gt on-dev' [rebased_branch: string = ""] {
  rebase-in-order "origin/develop" $rebased_branch
}

# Rebase a branch on origin/master
export def 'gt on-mast' [rebased_branch: string = ""] {
  rebase-in-order "origin/master" $rebased_branch
}

# Rebase a branch on origin/release/v2
export def 'gt on-v2' [rebased_branch: string = ""] {
  rebase-in-order "origin/release/v2" $rebased_branch
}

# Rebase a branch on HEAD
export def 'gt on-head' [rebased_branch: string] {
  rebase-in-order "HEAD" $rebased_branch
}

# Rebase the top commit of a branch on HEAD
export def 'gt on-head-1' [rebased_branch: string] {
  run-and-get-text { git rebase --onto HEAD $"($rebased_branch)~1" $rebased_branch }
}

# Rebase HEAD on a specific branch
export def 'gt head-on-arg' [target_commit: string] {
  rebase-in-order $target_commit "HEAD"
}

# Rebase one branch on another
export def 'gt in-order' [target_commit: string, rebased_branch: string] {
  rebase-in-order $target_commit $rebased_branch
}

# Continue rebasing
export def 'gt rebc' [] {
  run-and-get-text { git rebase --continue }
}

# Abort rebasing
export def 'gt reba' [] {
  run-and-get-text { git rebase --abort }
}

# Skip commit while rebasing
export def 'gt rebs' [] {
  run-and-get-text { git rebase --skip }
}

# Rebase interactively with a certain number of past commits
export def 'gt rebi' [count: int] {
  run-and-get-text { git rebase -i $"HEAD~($count)" }
}

# -----------------------------------------
# branches: mergetool
# -----------------------------------------

# Open mergetool
export def 'gt mt' [] {
  run-and-get-text { git mergetool };
}

# -----------------------------------------
# status: display
# -----------------------------------------

# Display status
export def 'gt st' [] {
  let lines: list<string> = run-and-get-lines { git status -s };
  let modified_files = $lines | each { |it|
    let status = $it | str substring 0..2 | str trim;
    let file_name = $it | str substring 2.. | str trim;
    { status: $status, file-name: $file_name }
  };
  mut rec = get-current-commit-info;
  if (($modified_files | length) > 0) {
    $rec.modified-files = $modified_files;
  }
  $rec
}

# -----------------------------------------
# cherry-picks
# -----------------------------------------

# Cherry-pick a commit
export def 'gt cp' [name: string] {
  run-and-get-text { git cherry-pick $name };
  { picked-commit: $name }
}

# Cherry-pick the content of a commit without actually committing
export def 'gt get' [name: string] {
  run-and-get-text { git cherry-pick -n $name };
  { picked-commit: $name }
}

# -----------------------------------------
# workspace: commit/store/hide
# -----------------------------------------

# Stage modification and new files
export def 'gt stg' [] {
  run-and-get-text { git add -A };
}

# Unstage all staged modifications
export def 'gt ustg' [] {
  run-and-get-text { git reset };
}

# Reset the workspace to the last commit, discarding all modifications
export def 'gt clr' [] {
  run-and-get-text { git reset --hard };
}

# Create a commit
export def 'gt ci' [] {
  run-and-get-text { git commit };
}

# Amend previous commit
export def 'gt ca' [] {
  run-and-get-text { git commit --amend --no-edit };
}

# Stash current modifications
export def 'gt hide' [] {
  run-and-get-text { git stash push -u };
}

# Get back previously stashed modifications
export def 'gt exh' [] {
  run-and-get-text { git stash pop };
}

# -----------------------------------------
# files
# -----------------------------------------

# Get file versions from another branch
export def 'gt fget' [commit: string, ...file_names: string] {
  run-and-get-text { git restore "--source" $commit ...$file_names };
}

# -----------------------------------------
# github
# -----------------------------------------

# Fetch from origin
export def 'gt fetch' [] {
  let output = run-and-get-output-obj { git fetch origin };
  $output.stderr | split row "\n"
  # | where { |it: string|
  #   ($it | str starts-with " * ") or ($it | str starts-with "   ")
  # } | each { |it|
  #   # let parts = $it | split row " " | where {|p| $p != "" };
  #   # let pcount = $parts | length;
  #   # if ($pcount == 6) {
  #   #   return { "local-ref": $parts.3, "remote-ref": $parts.5, "content": ($parts.1 + " " + $parts.2) };
  #   # } else if ($pcount == 4) {
  #   #   return { "local-ref": $parts.1, "remote-ref": $parts.3, "content": $parts.0 };
  #   # } else {
  #   #   return { "local-ref": "?", "remote-ref": "?", "content": $it };
  #   # }
  #   $it | str substring 3..
  # }
}

# Update and force push current branch to origin
export def 'gt force' [] {
  let branch = run-and-get-text { git rev-parse --abbrev-ref HEAD };
  if ($branch == "HEAD") {
    error make {
      msg: "Not on a branch",
      label: {
        text: "Not on a branch",
        span: (metadata $branch).span
      }
    };
  }
  run-and-get-text { git add -u };
  run-and-get-text { git commit --amend --no-edit };
  let output = run-and-get-output-obj { git push --force origin };
  $output.stderr | split row "\n" | where {|it| $it | str starts-with " + " }
}

# -----------------------------------------
# Environment setup
# -----------------------------------------

export-env {
  let os_name: string = (sys host).name;
  if $os_name == "Windows" {
    $env.GIT_SSH = 'C:\Program Files\PuTTY\plink.exe';
  }
}