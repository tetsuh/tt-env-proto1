# PATH setup for tt-env shims

`install.sh` installs two user-facing directories under `${TT_HOME}`:

- `${TT_HOME}/bin` contains the `tt-env` CLI.
- `${TT_HOME}/shims` contains generated command shims such as `tt-smi`.

If `TT_HOME` is unset, both `install.sh` and `tt-env` use `${HOME}/.tt-env`.
Add both directories to your shell PATH, with `shims` first:

## bash

Add this to `~/.bashrc`:

```bash
export PATH="${HOME}/.tt-env/shims:${HOME}/.tt-env/bin:${PATH}"
```

Reload the shell:

```bash
source ~/.bashrc
```

## zsh

Add this to `~/.zshrc`:

```zsh
export PATH="${HOME}/.tt-env/shims:${HOME}/.tt-env/bin:${PATH}"
```

Reload the shell:

```zsh
source ~/.zshrc
```

## fish

Run these once:

```fish
fish_add_path "${HOME}/.tt-env/shims" "${HOME}/.tt-env/bin"
```

## Verify

After installing tt-env and adding PATH entries, open a new shell and run:

```bash
tt-env --version
tt-env install --help
```

`tt-env use <release>` updates `${TT_HOME}/current`, and shims dispatch to
`${TT_HOME}/current/bin/<command>`. If no release is active, or if the active
release does not provide that command, shim commands fail instead of falling
through to unmanaged commands such as stale `${HOME}/.local/bin/tt-*` scripts.
