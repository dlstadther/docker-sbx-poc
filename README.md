# Claude Code in Docker Sandboxes

This repo runs Claude Code inside a Docker Sandboxes (`sbx`) microVM with your host Claude Code setup. Inside the sandbox, you get the following:

- Your host settings, skills, plugins, and rules, which the sandbox cannot change.
- Sessions that persist across sandbox restarts. `claude --resume` works.
- Session logs in the host `~/.claude/projects`, where you can read them.
- One `/login` that carries over to later sandboxes.
- The `gh` CLI with your host GitHub token, without the token inside the sandbox.

Tested with sbx v0.45.1 on macOS.

## Files

| File | Installed to | Purpose |
| --- | --- | --- |
| `sbxenv.yaml` | `~/.sbxenv.yaml` | Base environment for every `sbx env run`. `setup.sh` appends mounts for your machine. |
| `kit/claude-safe/spec.yaml` | `~/.sbx-kits/claude-safe/spec.yaml` | Kit that extends the `claude` agent. It sets `CLAUDE_CONFIG_DIR` and the GitHub credential. |
| `setup.sh` | not installed | Configures sbx on the host and installs the two files above. |

## Setup

1. Install Docker Sandboxes. On macOS, run `brew install --cask docker/tap/sbx`.
2. Run Claude Code on the host once, so that `~/.claude` exists.
3. Optional: run `gh auth login` on the host, so the sandbox can use `gh`.
4. Preview the generated environment file with `./setup.sh --print`. This step changes nothing.
5. Run `./setup.sh`.
6. In a project directory, run `sbx env run`.
7. On the first start, run `/login` inside Claude Code. Later sandboxes reuse this login.

`setup.sh` does these steps:

1. It sets `kit.allowedSources`, so the `github-ssh` mixin from `github.com/docker/` can load.
2. If no network policy exists yet, it sets the `deny-all` preset. Only the rules that kits declare then apply.
3. It stores your `gh auth token` as the `github` secret.
4. It installs the kit with your `$HOME` path.
5. It writes `~/.sbxenv.yaml`, with read-only mounts for the parts of `~/.claude` that exist on your machine.

If `~/.sbxenv.yaml` or the kit file exists, the script moves it to `*.bak.<timestamp>` before it writes the new file.

## How the mounts work

sbx mounts host paths at the same absolute path inside the sandbox. `CLAUDE_CONFIG_DIR` points Claude Code at your host `~/.claude`.

The `~/.claude` mount is writable, because Claude Code writes sessions, history, and the login file there. Read-only mounts below it protect the items in this list that exist on your machine: `skills`, `plugins`, `rules`, `agents`, `commands`, `output-styles`, `settings.json`, and `CLAUDE.md`.

Many setups use symlinks in `~/.claude`, for example into a dotfiles repo. If a mounted directory holds a symlink whose target is outside every mount, sbx fails to start the sandbox container. `setup.sh` finds these targets and mounts them read-only. For a target in a git repo, it mounts the repo root. Review these entries in the `--print` output.

## Adapt to your setup

- The network policy: set `SBX_POLICY=balanced ./setup.sh` for a less strict preset. The script sets the preset only on the first run.
- The kit sources: `sbx settings set kit.allowedSources` replaces the whole list. If you already allow other sources, run `SBX_ALLOWED_SOURCES='[...]' ./setup.sh` with your full list.
- The `github-ssh` mixin: if you do not need it, remove it from `sbxenv.yaml`.
- Other mounts: add entries to `additionalWorkspaces` in `sbxenv.yaml`, then re-run `./setup.sh`.

## Known limits

- Other top-level files in `~/.claude`, for example a statusline script, stay writable. To protect one, add it to `RO_FILES` in `setup.sh`.
- A sandbox can delete or replace a symlink in `~/.claude`. Writes through the link fail, but the link itself is in the writable mount. After a sandbox run, make sure that your links are intact.
- The login file `~/.claude/.credentials.json` is plain text on the host. On macOS, host Claude Code uses the Keychain and ignores this file.
- `setup.sh` supports only `~/.claude` as the host configuration folder.

## Troubleshooting

At sandbox creation, sbx applies kits, mounts, and environment variables. It does not apply them at a restart. `sbx env run` restarts an existing sandbox without these changes. The sandbox name is `claude-safe-<project directory name>`. `sbx ls` shows it.

To recreate a sandbox, run these commands in the project directory:

```
sbx rm claude-safe-<project directory name>
sbx env run
```

Recreate the sandbox in these cases:

- You changed `~/.sbxenv.yaml`, the kit, or re-ran `setup.sh`.
- Your settings, output style, or plugins are missing inside the sandbox. The sandbox is from before `CLAUDE_CONFIG_DIR` was set.
- You added or moved symlinks in `~/.claude`. Re-run `./setup.sh` first.

Other errors:

- `failed to run sandbox container`: a symlink in a mounted directory points outside every mount, or it is broken. Run `./setup.sh --print` to see broken links and the mounts it adds. On macOS, the daemon log names the path: `~/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/daemon.log`. Fix the link, re-run `./setup.sh`, and recreate the sandbox.
- `sbx env rm` reports `sandbox not found`: use `sbx ls` to find the name, then `sbx rm <name>`.
- `GH_TOKEN` shows `proxy-managed`: this is correct. The proxy adds the real token to requests to `api.github.com`. If `gh` still fails, run `gh auth login` on the host, then re-run `./setup.sh`.
- A kit error that names `invalid repository` or `not a valid zip file`: a kit source must be a directory path that starts with `./`. Kit sources do not accept `~` or `$HOME`.
- A git kit is not allowed: add its source to `kit.allowedSources`.
- `sbx policy init` reports that the policy is already initialized: this is expected on a re-run. The existing policy stays.
