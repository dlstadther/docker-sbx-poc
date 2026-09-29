# Python and uv sample

This sample is a project sandbox for a Python project that uses uv and gets its packages from Artifactory. It comes
from a real project, called the source project here. It adds a project template to the [base sample](../base/README.md). A template
is the image that sbx starts the sandbox from.

## What the sample supports

In the sandbox, these commands work:

- `uv sync --frozen` installs packages from Artifactory. The sbx proxy adds your Artifactory token.
- `uv add <package>` adds a new package to `pyproject.toml` and `uv.lock`. You do not rebuild the template.
- `make lint` and `make test` run ruff, sqlfluff, and pytest.
- `git commit`, `git push`, `gh api`, and `gh pr list` work.
- Web search works.

The sandbox cannot do these things:

- It cannot read your Artifactory or GitHub token. It sees only the value `proxy-managed`.
- It cannot use the gcloud or bq CLIs. The template does not install them, and the network blocks Google hosts.
- It cannot run `docker build`. The sandbox has no Docker daemon.
- It cannot download Python builds. The template holds them, and `UV_PYTHON_DOWNLOADS=never` stops uv from downloading
  them.

When a Python version, uv, or a system package changes, you rebuild the template. Package changes need no rebuild.

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile.sbx` | Builds the template with uv, two Python versions, a C compiler, and a `python` command. |
| `sbxenv.yaml` | Names the template and turns off Python downloads. |
| `sbx.sh` | Builds and loads the template, and starts or recreates the sandbox. It is the same as in the base sample. |

The `claude-safe` kit sets two uv values for all sandboxes:

- `UV_DEFAULT_INDEX` points uv at Artifactory. The URL has no token.
- `UV_PROJECT_ENVIRONMENT=.venv-sbx` puts the sandbox venv in `.venv-sbx`. The host `.venv` links to a macOS Python,
  so the sandbox cannot use it. The name is relative, so each uv project and subproject gets its own sandbox venv.

## Use the sample in your project

Before you start, run `./setup.sh` in this repo, and log in to Artifactory with uv. Start Docker Desktop.

1. Copy the three files to the root of your project.
2. Add `.venv-sbx/` to `.git/info/exclude` or `.gitignore` in your project.
3. In `sbxenv.yaml`, change `python-uv-sbx` in the template name to a short name for your project.
4. In `Dockerfile.sbx`, change the Python versions in `uv python install` to the versions in your project. Use the
   versions in `.python-version`, `mise.toml`, or `requires-python`.
5. In `Dockerfile.sbx`, replace `XXXXXX.jfrog.io` in the `uv.toml` URL with your JFrog host.
6. In `Dockerfile.sbx`, remove the parts that your project does not need. See the next section.
7. In your project, run `./sbx.sh`.
8. In the sandbox, run `uv sync`, then your lint and test commands. Make sure that they pass.

## Parts of Dockerfile.sbx that are specific to the source project

These parts are in the template because of the source project scripts. If your project does not need
a part, remove it.

- `build-essential`: the package `iteration-utilities` has no wheel for Linux arm64, so uv compiles it on Apple
  silicon. If `uv sync` shows `No such file or directory: 'cc'`, keep this part.
- The `python` script in `/usr/local/bin`: the make scripts compare `python --version` with the nearest
  `.python-version` file. The script runs the Python that `uv python find` selects for the current directory. mise does
  the same on the host. If your scripts use only `uv run`, remove this part.
- `~/.config/uv/uv.toml`: if this file does not exist, the scripts exit. The file holds only the Artifactory URL and no
  token.
- The empty `auth.toml`, `pip.conf`, and `.pypirc` files: if these Poetry and pip files do not exist, the scripts exit.
  uv does not read them.

## Details to know

- `.git/config` in the source project sets `core.hooksPath` to an empty value, so `git commit` does not run the
  pre-commit hooks. Before each commit, run the hooks by hand:

  ```
  PIP_INDEX_URL=$UV_DEFAULT_INDEX uv run pre-commit run --files <changed files>
  ```

  pre-commit uses pip to build its hook environments, and the network blocks `pypi.org`. `PIP_INDEX_URL` sends pip to
  Artifactory.
- In the source project, `make test_airflow` runs `make library`, which needs a value in `GITHUB_TOKEN`. Before you run
  it, run `export GITHUB_TOKEN=proxy-managed`. The proxy adds the real token to requests to `api.github.com`.
- `uv add` moves the `[[tool.uv.index]]` block to a different place in `pyproject.toml`. To keep the diff small, move
  the block back.
- After `./sbx.sh recreate`, `.venv-sbx` stays in the project directory, so `uv sync` reuses the installed packages.
