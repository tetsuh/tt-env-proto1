# Manual verification checklist

Use this template in pull request descriptions. It expands the required
verification log from `ISSUE_GUIDELINES.md` section 6 while keeping the same
required fields.

## Pull request template

````markdown
### Verification

- [ ] `bash scripts/lint.sh` - paste tail of output

  ```text
  <paste the final lines, for example: lint passed>
  ```

- [ ] `bash scripts/test.sh` - paste tail of output

  ```text
  <paste the final lines, for example: 166 tests, 0 failures>
  ```

- [ ] Manual scenario(s): <list>

  - [ ] Install: `tt-env install <release>`
  - [ ] Use: `tt-env use <release>` (verify with `readlink ~/.tt-env/current`)
  - [ ] Status: `tt-env status`
  - [ ] Update: `tt-env update`
  - [ ] Self-update: `tt-env update --self`

- [ ] Host: <Ubuntu 22.04 / WSL2 / container>; HW present: <yes/no>

  - OS: <contents of `/etc/os-release` ID and VERSION_ID>
  - Kernel: <output of `uname -r`>
  - Secure Boot: <output of `mokutil --sb-state`, or "not available">
  - Tenstorrent hardware: <yes/no; include `lspci -d 1e52:` summary if yes>
  - Manifest source: <default / override URL / private repo>
  - Simulated steps: <none, or list steps not run on real hardware>
  - Deviations: <none, or describe>
````

## Manual scenario notes

For pure documentation changes, list the manual scenario as "not applicable"
and explain why. For code, installer, KMD, manifest, or self-update changes,
include the relevant commands from `docs/e2e.md` and paste the important output
or failure transcript.

When a scenario cannot be exercised without real Tenstorrent hardware, keep the
checkbox unchecked or mark it as simulated, then state exactly which command was
simulated and which command was run on real hardware.

## Expected command coverage

| Area | Command or evidence |
|---|---|
| Lint | `bash scripts/lint.sh` |
| Test | `bash scripts/test.sh` |
| Install | `tt-env install <release>` |
| Use | `tt-env use <release>` and `readlink ~/.tt-env/current` |
| Status | `tt-env status` |
| Update | `tt-env update` |
| Self-update | `tt-env update --self` |

Use `docs/e2e.md` for the full Ubuntu 22.04 end-to-end transcript checklist.
