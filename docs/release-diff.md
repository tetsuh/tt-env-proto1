# Comparing stack releases

Use `tt-env diff` to compare two release manifests before switching between
dated Tenstorrent stack releases:

```sh
tt-env diff 2026.05.16 2026.08.16
```

The output includes stack `components`, system package pins, and release-local
Python package pins. Missing values are shown as `-`.

This command compares manifest metadata only. System-global state such as the
loaded KMD module is not changed by `tt-env diff` and cannot be switched by
`tt-env use` alone.
