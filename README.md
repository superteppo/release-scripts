# Release Scripts

Small Bash tasks for consistent numbered GitHub releases. The project owns Git
commits, tags, changelogs, and GitHub Releases. Your package manager remains in
charge of package metadata and lockfiles.

## Requirements

- Bash, Git, and [GitHub CLI](https://cli.github.com/)
- A clean working tree and an `origin` remote
- GitHub CLI authentication completed for the target repository

[mise](https://mise.jdx.dev/) is optional. When mise is present and `gh` is
missing, the release scripts can use a mise-managed `gh@2` instead.

## Install

### Standalone

From the target repository, install the latest stable scripts:

```console
curl -fsSL https://raw.githubusercontent.com/superteppo/release-scripts/main/install.sh | bash
./.release-scripts/release setup
```

The installer adds only the runtime scripts, templates, and license notices
under `.release-scripts`. It records the selected update channel and resolved
Git commit. Review and commit that directory when releases must work without an
installation step in CI.

Update to the newest stable release, or follow the newest patch in a release
series without knowing its exact version:

```console
./.release-scripts/release update latest
./.release-scripts/release update 1.5
./.release-scripts/release update       # keep the selected channel
```

Exact versions such as `1.5.0` are also accepted. `latest` resolves the highest
stable version tag; `1.5` follows the moving `v1.5` tag.

Standalone configuration is stored in `.release.env`. It is trusted Bash owned
by the target project, because release hooks are shell commands. Preview or
accept the guided setup defaults with:

```console
./.release-scripts/release setup --dry-run
./.release-scripts/release setup --yes
```

### With mise

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
local entries above keep existing and future file tasks discoverable. Keep them
even when their directories are empty; remove one only when deliberately
disabling that task directory.

This tracks toolkit updates without copying scripts. For reproducible builds,
replace `main` with an exact release such as `v1.4.0`. mise caches remote tasks;
run `mise cache clear` to refresh them immediately.

Then run the guided setup:

```console
mise run release:setup
```

Both setup variants detect npm, Poetry, uv, or tag-only versioning; offer moving
tags and Conventional Commit hooks; preserve existing release variables; and
finish with the doctor checks. The mise variant writes environment defaults
through mise. Preview or accept its recommended answers with:

```console
mise run release:setup --dry-run
mise run release:setup --yes
```

Dry-run still asks questions because the answers determine the plan being
previewed. Proposed actions are shown in both modes; only normal mode offers the
final apply confirmation.

For GitHub Action repositories, `--yes` enables the recommended major moving
alias such as `v1`. In other repositories moving tags remain opt-in. GitHub
authentication is intentionally not automated; follow a doctor error with
`gh auth login` or, with mise, `mise exec gh@2 -- gh auth login`.

### Install with Claude Code or Codex

Paste this into the coding agent while it is working in the target repository:

```text
Read and follow the integration instructions in:
https://github.com/superteppo/release-scripts/blob/main/README.md

Install the release scripts in this repository. Use the existing mise integration
when mise is already configured; otherwise use the standalone installation.
Inspect package-manager configuration and preserve existing version-management
behavior. Run the release doctor, but do not create a release. Keep changes
minimal and summarize them.
```

## Configure version ownership

The release task calculates an exact version and exports:

- `RELEASE_VERSION`, for example `1.4.0-rc.1`
- `RELEASE_VERSION_PEP440`, for example `1.4.0rc1`
- `RELEASE_TAG`, for example `v1.4.0-rc.1`

Configure commands that read and set that exact version. Configure both or
neither.

Pin the project's package and build tools so the same command versions are used
locally and in CI.

### npm

```bash
RELEASE_GET_VERSION='npm pkg get version --workspaces=false | tr -d "\""'
RELEASE_SET_VERSION='npm version --no-git-tag-version --ignore-scripts "$RELEASE_VERSION"'
RELEASE_CHECK_COMMAND='npm test'
RELEASE_BUILD_COMMAND='npm run build'
RELEASE_ARTIFACTS='dist/*.tgz'
RELEASE_MOVING_TAGS='major minor'
```

### Poetry

```bash
RELEASE_GET_VERSION='poetry version --short'
RELEASE_SET_VERSION='poetry version "$RELEASE_VERSION_PEP440"'
RELEASE_CHECK_COMMAND='poetry run pytest'
RELEASE_BUILD_COMMAND='poetry build'
RELEASE_ARTIFACTS='dist/*.whl dist/*.tar.gz'
```

### uv

```bash
RELEASE_GET_VERSION='uv version --short'
RELEASE_SET_VERSION='uv version "$RELEASE_VERSION_PEP440"'
RELEASE_CHECK_COMMAND='uv run pytest'
RELEASE_BUILD_COMMAND='uv build'
RELEASE_ARTIFACTS='dist/*.whl dist/*.tar.gz'
```

For VCS-derived versions, omit both version commands. Git tags then remain the
only version source. If existing tags are unprefixed (`1.2.3`), also set
`RELEASE_TAG_PREFIX=''`; otherwise the default is `v1.2.3`. Custom and
monorepo workflows can use any commands that obey the same get/set contract.

## Project defaults

Standalone users set reusable defaults in `.release.env`:

```bash
RELEASE_MOVING_TAGS='major minor'
RELEASE_BRANCH_PATTERN='main|release/.+|fix/.+'
# Replace these examples with commands and artifacts provided by the project.
RELEASE_CHECK_COMMAND='node --test'
RELEASE_BUILD_COMMAND='npm run build'
RELEASE_ARTIFACTS='dist/*.zip'
```

Mise users put the same variables under `[env]` in `mise.toml`. Command-line
options override the corresponding project default.

By default, releases are allowed only from GitHub's default branch. Set
`RELEASE_BRANCH_PATTERN` to an extended regular expression when dedicated
release or fix branches are also allowed. The expression must match the entire
branch name.

## Release

```console
./.release-scripts/release patch
./.release-scripts/release auto
./.release-scripts/release --pre
./.release-scripts/release --pre minor
./.release-scripts/release --promote
./.release-scripts/release --dry-run patch
./.release-scripts/release --moving-tags major,minor patch
```

With mise, replace `./.release-scripts/release` with `mise run release`.

The task checks dependencies, GitHub authentication, versions, configured
checks, builds, and artifacts. It then updates `CHANGELOG.md`, creates a release
commit and annotated tag, pushes them, and creates the GitHub Release with `gh`.
Release assets are replaced safely when GitHub publishing is retried.

### Release thresholds

For frequent deployments, keep patch releases small while keeping full
changelogs for minor and major releases:

```sh
./.release-scripts/release auto --changelog minor --release patch
```

`--changelog minor` updates the changelog file for minor and major releases.
Patch releases still get generated notes, a Git tag, and a GitHub Release, but
do not update the changelog file or run a custom changelog hook. Tag-based
projects therefore need no release commit for patches; package-version changes
still get committed. Checks, builds and artifact validation always run.

`--release patch` publishes a GitHub Release for every bump. Set it to `minor`
or `major` to publish Git tags without GitHub Releases below that threshold.
Both options accept `patch`, `minor`, `major`, or `none`; `none` disables that
output. Both default to `patch`, preserving the existing full release flow.
Release candidates and promotions use their base version bump for thresholds.

The matching configuration is:

```sh
RELEASE_CHANGELOG_THRESHOLD='minor'
RELEASE_GITHUB_THRESHOLD='patch'
```

Put it in `.release.env` (or `[env]` in `mise.toml`). Command-line thresholds
override these settings. `--no-publish` and `--dry-run` work as usual. To retry
publishing only Git refs, use `release github TAG --tag-only`.

### Changelog entries

An entry lists every commit since the previous release except the
`chore(release):` commits this task creates itself. Commits are grouped by their
Conventional Commit type, in this order:

1. `breaking`, holding every `type!:` commit whatever its type.
2. The types named by Conventional Commits 1.0.0: `feat`, `fix`, `docs`, `perf`,
   `refactor`, `test`, `style`, `build`, `ci`, `chore`.
3. Any project-specific type, alphabetically.
4. `other`, for commits without a recognizable type.

Empty groups are left out. Scopes are kept, and each commit links to itself
relative to the repository root:

```markdown
### breaking

- **feat(api):** drop the v1 endpoint ([`35e452c`](../../commit/35e452cdf863…))

### feat

- **api:** add batch endpoint ([`b10797a`](../../commit/b10797aa2af6…))
```

A breaking commit appears only under `breaking`, where its own type prefixes the
subject. Only the `!` marker is read; `BREAKING CHANGE:` in a commit body is not
detected.

Relative links follow forks and GitHub Enterprise hosts without configuration.
The link depth is computed for the changelog's own path, so it resolves from the
rendered changelog. The same entry is reused as the GitHub Release body, which
is rendered from a different URL; check the first published release if those
links matter.

Moving tags are optional. For a stable `v2.3.0` release, `major minor` updates
`v2` and `v2.3` to the same commit. They are force-updated atomically with the
immutable release tag. Prereleases never move these aliases.

### Release candidates

`--pre` creates `X.Y.Z-rc.N` tags and never moves the stable aliases. The bump
is optional:

- With no unpromoted rc tag, `--pre` alone behaves like `--pre auto`.
- With an unpromoted rc tag, `--pre` alone keeps `X.Y.Z` and advances the
  candidate number, so `v1.5.0-rc.1` becomes `v1.5.0-rc.2`.
- An explicit bump that lands on the same `X.Y.Z` also advances the candidate
  number. One that lands higher starts that version at `rc.1`, so `--pre major`
  turns an unpromoted `v1.5.0-rc.2` into `v2.0.0-rc.1`.
- An explicit bump that lands below an unpromoted rc stops the release.

An rc tag counts as unpromoted while its `X.Y.Z` is ahead of the latest stable
tag. `--promote` then releases the candidate's `X.Y.Z` as a stable version.

The changelog keeps only stable entries and the candidates released after the
newest stable one. Each candidate entry lists the commits added since the
previous candidate. Promoting replaces those entries with a single stable entry
covering every commit since the previous stable tag, so nothing is lost.

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
./.release-scripts/release setup-hooks
pre-commit run --all-files
```

With mise, run `mise run release:setup-hooks`. The setup task uses the project's
active pre-commit when available; otherwise mise automatically installs
pre-commit 4. Without mise, install pre-commit first. It installs both
`pre-commit` and `commit-msg` Git hooks. If `.pre-commit-config.yaml` is absent, it creates a
minimal configuration with Commitizen validation pinned to `v4.10.0`. Existing
tool and hook configuration is validated and left unchanged; its rules remain
owned by the target project. Review and commit a newly generated configuration.
Pre-commit complements `RELEASE_CHECK_COMMAND`; the latter remains the
authoritative release gate.

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

```bash
RELEASE_CHANGELOG='false'
RELEASE_CHANGELOG_COMMAND='./scripts/release-changelog.sh "$RELEASE_PREVIOUS_TAG" "$RELEASE_VERSION" "$RELEASE_NOTES_FILE"'
```

The command also receives `RELEASE_TAG`. Tracked files it changes are included
in the release commit; it should `git add` any newly created changelog files.

### Tag prefix

Tags use `vX.Y.Z` by default. To create `X.Y.Z` tags instead, set an explicitly
empty prefix in `.release.env` or the mise environment:

```bash
RELEASE_TAG_PREFIX=''
```

When moving tags are enabled, their names likewise become `X` and `X.Y`.
For repositories that publish a GitHub Action, prefer
`RELEASE_MOVING_TAGS = "major"` so consumers can use a stable alias such as
`owner/action@v1`.

Create only the local commit and tag:

```console
./.release-scripts/release --no-publish patch
./.release-scripts/release github v1.2.3
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
  `./.release-scripts/release github <tag>` (or `mise run release:github <tag>`).
  If moving tags were supplied only on the
  command line, repeat `--moving-tags major,minor` during the retry.
- Inspect the next operation without changes using `--dry-run`; dirty working
  trees are allowed and GitHub authentication is not required.

## Optional Dropbox publishing

The Dropbox publisher is separate from the GitHub release flow:

```bash
RELEASE_ARTIFACTS='dist/*.zip'
RELEASE_DROPBOX_PATH='my-project/releases'
```

Add a configured `.dropboxuploader` file, then run:

```console
./.release-scripts/release dropbox
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
