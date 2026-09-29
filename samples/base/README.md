# Base sample

This sample is a starting point for a project sandbox. Copy it into a project, then add the tools that the project
needs. For a full example, see [python-uv](../python-uv/README.md).

## What the sample supports

The sandbox runs Claude Code with the `claude-safe` kit from this repo. The kit gives the sandbox these items:

- Your host Claude Code setup, from the `~/.claude` mounts in `~/.sbxenv.yaml`.
- The `gh` CLI and the GitHub API. The sbx proxy adds your GitHub token to requests to `api.github.com`.
- Git over SSH. The sandbox uses your host SSH agent. See [Git over SSH](../../README.md#git-over-ssh).
- Packages from Artifactory. The sbx proxy adds your Artifactory token to requests to your JFrog host.
- Web search. Claude Code runs web search on Anthropic servers, so it needs no network rule.

The `deny-all` network policy blocks all other hosts. The sandbox has no real token values. It sees only the value
`proxy-managed`.

The sample adds a project template. A template is the image that sbx starts the sandbox from. You build it on the host,
where the network is open. Tools and system packages come from the template, so the sandbox needs no network access to
apt or other download hosts.

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile.sbx` | Builds the project template from `docker/sandbox-templates:claude-code`. |
| `sbxenv.yaml` | Names the template and mounts the git folder. `sbx env run` merges `~/.sbxenv.yaml` beneath it. |
| `sbx.sh` | Builds and loads the template, and starts or recreates the sandbox. |

## Use the sample in your project

Before you start, run `./setup.sh` in this repo, and start Docker Desktop.

1. Copy the three files to the root of your project.
2. In `sbxenv.yaml`, change `my-project` in the template name to a short name for your project.
3. In `Dockerfile.sbx`, add the system packages and language runtimes that your project needs.
4. In your project, run `./sbx.sh`. The script builds the template, loads it into sbx, and starts the sandbox.
5. In the sandbox, run your project's build, lint, and test commands. Make sure that they pass.

If a command fails because the network blocks a host, run `sbx policy log` on the host to see the blocked host. Then
select one of these fixes:

- If the command downloads a tool or a runtime, install it in `Dockerfile.sbx`.
- If the command downloads a package, get the package through Artifactory.
- If the sandbox needs the host for a short time, allow it for one sandbox with `sbx policy allow network`. Remove the
  rule after use.

Do not add a host to the kit for one project. The kit applies to all sandboxes.

If you do not want to commit the files to the project, add them to `.git/info/exclude`.

## Git worktrees

In a git worktree, `.git` is a file that points into the `.git` folder of the main repository. That folder is outside
the project directory, so sbx does not mount it with the workspace. Without it, every git command fails with
`fatal: not a git repository`.

`sbx.sh` gets the folder path from `git rev-parse --git-common-dir` on the host and gives it to `sbxenv.yaml` as the
`gitCommonDir` argument. `sbxenv.yaml` mounts the folder read/write at the same path. In the main checkout, the folder
is in the workspace already, but the read-only rules below also apply.

The mount makes `hooks/` and `config` read-only. Git on the host runs the hooks and the commands that `config` names,
for example `core.hooksPath` and `core.fsmonitor`. A writable copy lets the sandbox run commands on the host. Commands
that write `config` fail in the sandbox, for example `git push -u` and `git branch --set-upstream-to`. Use
`git push origin HEAD`. If you use `gh pr create`, give it `--head <branch>`.

Start the sandbox with `sbx.sh`. If you run `sbx env run` directly, it stops because `gitCommonDir` has no value.

Do not run `git worktree prune` in the sandbox. The sandbox does not mount your other worktrees, so git thinks that they
were deleted and removes their records. To remove one worktree, run `git worktree remove <path>`.

## sbx.sh commands

| Command | Action |
| --- | --- |
| `./sbx.sh` | If sbx does not have the template, builds it. Then starts or attaches to the sandbox. |
| `./sbx.sh build` | Builds the template. If the image changed, loads it into sbx. |
| `./sbx.sh rebuild` | Builds the template without the Docker cache, then loads it. Use it to get new tool versions. |
| `./sbx.sh recreate` | Removes the sandbox, then creates and starts it again. |

A sandbox keeps its template, kit, and `sbxenv.yaml` from the time that sbx created it. After you change one of them,
run `./sbx.sh recreate`. Your Claude Code sessions stay, because they are in the host `~/.claude`.

The sandbox name is `claude-safe-<project directory name>`. If you change the agent in `~/.sbxenv.yaml`, change the
`SANDBOX` value in `sbx.sh`.
