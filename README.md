# Release Scripts

Small Bash tasks for consistent numbered GitHub releases. The project owns Git
commits, tags, changelogs, and GitHub Releases. Your package manager remains in
charge of package metadata and lockfiles.

## Requirements

- Bash, Git, [mise](https://mise.jdx.dev/), and [GitHub CLI](https://cli.github.com/)
- A clean working tree and an `origin` remote
- `gh auth login` completed for the target repository

## Install

Add the remote task catalog to the target project's `mise.toml`:

```toml
[task_config]
includes = [
  "mise-tasks",
  ".mise-tasks",
  ".mise/tasks",
  ".config/mise/tasks",
  "mise/tasks",
  "git::https://github.com/superteppo/release-scripts.git//mise-tasks?ref=main"
]
```

Setting `task_config.includes` replaces mise's default task directories. The
local entries above keep existing file tasks discoverable; remove only the
directories the target project does not use.

This tracks toolkit updates without copying scripts. For reproducible builds,
replace `main` with an exact release such as `v1.0.0`. mise caches remote tasks;
run `mise cache clear` to refresh them immediately.

Check the setup:

```console
mise run release:doctor
```

### Install with Claude Code or Codex

Paste this into the coding agent while it is working in the target repository:

```text
Read and follow the integration instructions in:
https://github.com/superteppo/release-scripts/blob/main/README.md

Integrate the release task catalog into this repository. Inspect the existing
mise and package-manager configuration before editing. Preserve local mise tasks
and existing version-management behavior. Configure only the relevant release
options, run `mise run release:doctor`, and do not create a release. Keep changes
minimal and summarize them.
```

## Configure version ownership

The release task calculates an exact version and exports:

- `RELEASE_VERSION`, for example `1.4.0-rc.1`
- `RELEASE_VERSION_PEP440`, for example `1.4.0rc1`
- `RELEASE_TAG`, for example `v1.4.0-rc.1`

Configure commands that read and set that exact version. Configure both or
neither.

### npm

```toml
[env]
RELEASE_GET_VERSION = "npm pkg get version --workspaces=false | tr -d '\"'"
RELEASE_SET_VERSION = "npm version --no-git-tag-version --ignore-scripts \"$RELEASE_VERSION\""
RELEASE_CHECK_COMMAND = "npm test"
RELEASE_BUILD_COMMAND = "npm run build"
RELEASE_ARTIFACTS = "dist/*.tgz"
RELEASE_MOVING_TAGS = "major minor"
```

### Poetry

```toml
[env]
RELEASE_GET_VERSION = "poetry version --short"
RELEASE_SET_VERSION = "poetry version \"$RELEASE_VERSION_PEP440\""
RELEASE_CHECK_COMMAND = "poetry run pytest"
RELEASE_BUILD_COMMAND = "poetry build"
RELEASE_ARTIFACTS = "dist/*.whl dist/*.tar.gz"
```

### uv

```toml
[env]
RELEASE_GET_VERSION = "uv version --short"
RELEASE_SET_VERSION = "uv version \"$RELEASE_VERSION_PEP440\""
RELEASE_CHECK_COMMAND = "uv run pytest"
RELEASE_BUILD_COMMAND = "uv build"
RELEASE_ARTIFACTS = "dist/*.whl dist/*.tar.gz"
```

For VCS-derived versions, omit both version commands. Git tags then remain the
only version source. If existing tags are unprefixed (`1.2.3`), also set
`RELEASE_TAG_PREFIX = ""`; otherwise the default is `v1.2.3`. Custom and
monorepo workflows can use any commands that obey the same get/set contract.

## Project defaults

Set reusable defaults in the target project's existing `mise.toml`:

```toml
[env]
RELEASE_MOVING_TAGS = "major minor"
RELEASE_BRANCH_PATTERN = "main|release/.+|fix/.+"
RELEASE_CHECK_COMMAND = "mise run test"
RELEASE_BUILD_COMMAND = "mise run build"
RELEASE_ARTIFACTS = "dist/*.zip"
```

Command-line options override the corresponding mise default.

By default, releases are allowed only from GitHub's default branch. Set
`RELEASE_BRANCH_PATTERN` to an extended regular expression when dedicated
release or fix branches are also allowed. The expression must match the entire
branch name.

## Release

```console
mise run release patch
mise run release auto
mise run release minor
mise run release major
mise run release --pre minor
mise run release --pre auto
mise run release --promote
mise run release --dry-run patch
mise run release --moving-tags major,minor patch
```

The task checks dependencies, GitHub authentication, versions, configured
checks, builds, and artifacts. It then updates `CHANGELOG.md`, creates a release
commit and annotated tag, pushes them, and creates the GitHub Release with `gh`.
Release assets are replaced safely when GitHub publishing is retried.

Moving tags are optional. For a stable `v2.3.0` release, `major minor` updates
`v2` and `v2.3` to the same commit. They are force-updated atomically with the
immutable release tag. Prereleases never move these aliases.

### Automatic version bump

Use `auto` to inspect commit messages from the latest stable `X.Y.Z` tag through
`HEAD`:

- `BREAKING CHANGE:` or `type!:` selects `major`.
- `feat:` selects `minor`.
- `fix:` selects `patch`.
- Other commit types have no implicit release effect; if none of the rules
  match, the release stops.

The highest matching change wins. Types and optional scopes follow
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
For predictable `auto` releases, adopt Conventional Commits for every
release-worthy change and enforce the format with a commit-message check or CI.

### Recommended safeguards

Use [pre-commit](https://pre-commit.com/) for fast, project-specific checks
before changes enter release history:

```console
pre-commit install
pre-commit run --all-files
```

Keep the hook configuration in the target repository. Pre-commit complements
`RELEASE_CHECK_COMMAND`; the latter remains the authoritative release gate.

### GitHub Actions

Use [the included workflow](.github/workflows/github-actions-release.yaml). It
runs only when manually dispatched, defaults to a Conventional Commits `auto`
bump, and creates the commit, tags, and GitHub Release without manual tag
creation:

```console
gh workflow run github-actions-release.yaml -f bump=auto
```

The workflow checks out the default branch with complete commit/tag history for
version inference and changelogs. `filter: blob:none` avoids eagerly downloading
historical file contents. Pin the remote task catalog in `mise.toml` to the exact
toolkit release used by CI, for example `ref=v1.3.0`, instead of `ref=main`.

The default `GITHUB_TOKEN` needs `contents: write`. Its pushes and releases do
not trigger ordinary downstream workflows. If package publishing depends on a
`push` or `release` workflow, use a suitably restricted GitHub App token or PAT
for both the checkout `token` and `GH_TOKEN`. Repository rules must also permit
the release commit and immutable/moving tag updates; signed-commit or protected
tag requirements may need repository-specific configuration.

### Changelog customization

The built-in generator updates `RELEASE_CHANGELOG` and writes GitHub release
notes. For a bespoke format, disable the built-in changelog file and configure
a command that writes the exported `$RELEASE_NOTES_FILE`:

```toml
[env]
RELEASE_CHANGELOG = "false"
RELEASE_CHANGELOG_COMMAND = "./scripts/release-changelog.sh \"$RELEASE_PREVIOUS_TAG\" \"$RELEASE_VERSION\" \"$RELEASE_NOTES_FILE\""
```

The command also receives `RELEASE_TAG`. Tracked files it changes are included
in the release commit; it should `git add` any newly created changelog files.

### Tag prefix

Tags use `vX.Y.Z` by default. To create `X.Y.Z` tags instead, set an explicitly
empty prefix in `mise.toml`:

```toml
[env]
RELEASE_TAG_PREFIX = ""
```

When moving tags are enabled, their names likewise become `X` and `X.Y`.
For repositories that publish a GitHub Action, prefer
`RELEASE_MOVING_TAGS = "major"` so consumers can use a stable alias such as
`owner/action@v1`.

Create only the local commit and tag:

```console
mise run release --no-publish patch
mise run release:github v1.2.3
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RELEASE_GET_VERSION` | tags | Print the current package version |
| `RELEASE_SET_VERSION` | none | Set `$RELEASE_VERSION` using the owning tool |
| `RELEASE_CHECK_COMMAND` | none | Tests or validation before release |
| `RELEASE_BUILD_COMMAND` | none | Build release artifacts |
| `RELEASE_ARTIFACTS` | none | Space-separated artifact globs |
| `RELEASE_TAG_PREFIX` | `v` | Prefix for release tags; may be empty |
| `RELEASE_MOVING_TAGS` | none | Moving stable aliases: `major`, `minor`, or both |
| `RELEASE_BRANCH_PATTERN` | default branch | Allowed release branch regex |
| `RELEASE_CHANGELOG` | `CHANGELOG.md` | Changelog path; use `false` to disable |
| `RELEASE_CHANGELOG_COMMAND` | built-in generator | Custom command that writes `$RELEASE_NOTES_FILE` |

The configured commands are executed as trusted Bash. Artifact filenames may
contain spaces, but the glob patterns themselves may not.

## Recovery

- Before a tag is created: inspect or revert changes made by the configured
  version/build commands, then rerun from a clean tree.
- After a tag is created: retry only publication with
  `mise run release:github <tag>`. If moving tags were supplied only on the
  command line, repeat `--moving-tags major,minor` during the retry.
- Inspect the next operation without changes using `--dry-run`; dirty working
  trees are allowed and GitHub authentication is not required.

## Optional Dropbox publishing

The Dropbox publisher is separate from the GitHub release flow:

```toml
[env]
RELEASE_ARTIFACTS = "dist/*.zip"
RELEASE_DROPBOX_PATH = "my-project/releases"
```

Add a configured `.dropboxuploader` file, then run:

```console
mise run release:dropbox
```

This task uses the bundled `tools/dropbox_uploader.sh`; a project-local uploader
is not used. `RELEASE_DROPBOX_PATH` defaults to
`<repository-directory>/releases`, so set it explicitly when the public project
name differs. The task uploads only `RELEASE_ARTIFACTS` plus the configured
changelog. Include files such as `version.txt` in `RELEASE_ARTIFACTS` when they
must also be published.

## Development

Install the local safeguard once:

```console
pre-commit install
```

It runs Bash syntax checks, ShellCheck, integration tests, and whitespace
validation before every commit. Run the same gate manually with:

```console
tests/check.sh
# or
pre-commit run --all-files
```

## License and acknowledgements

Release Scripts is available under the [MIT License](LICENSE). Commercial use
and derivative works are permitted.

`tools/dropbox_uploader.sh` is the
[Dropbox-Uploader](https://github.com/andreafabrizi/Dropbox-Uploader) script by
Andrea Fabrizi and contributors. It retains its GPLv3-or-later license. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
