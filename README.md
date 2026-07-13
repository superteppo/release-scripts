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
  "git::https://github.com/superteppo/release-scripts.git//mise-tasks?ref=v1"
]
```

Pin a tag such as `v1` for stable updates. Use `ref=main` only when immediate
changes are wanted. mise caches remote tasks; run `mise cache clear` to refresh
them immediately.

Check the setup:

```console
mise run release:doctor
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
only version source. Custom and monorepo workflows can use any commands that
obey the same get/set contract.

## Release

```console
mise run release patch
mise run release minor
mise run release major
mise run release --pre minor
mise run release --promote
mise run release --dry-run patch
```

The task checks versions, runs configured checks and builds, verifies artifacts,
updates `CHANGELOG.md`, creates a release commit and annotated tag, pushes them,
then creates the GitHub Release with `gh`. Release assets are replaced safely
when GitHub publishing is retried.

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
| `RELEASE_CHANGELOG` | `CHANGELOG.md` | Changelog path; use `false` to disable |

The configured commands are executed as trusted Bash. Artifact filenames may
contain spaces, but the glob patterns themselves may not.

## Recovery

- Before a tag is created: inspect or revert changes made by the configured
  version/build commands, then rerun from a clean tree.
- After a tag is created: retry only publication with
  `mise run release:github <tag>`.
- Inspect the next operation without changes using `--dry-run`.

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

## License and acknowledgements

Release Scripts is available under the [MIT License](LICENSE). Commercial use
and derivative works are permitted.

`tools/dropbox_uploader.sh` is the
[Dropbox-Uploader](https://github.com/andreafabrizi/Dropbox-Uploader) script by
Andrea Fabrizi and contributors. It retains its GPLv3-or-later license. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
