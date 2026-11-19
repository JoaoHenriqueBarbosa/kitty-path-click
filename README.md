# kitty-path-click

[kitty](https://github.com/kovidgoyal/kitty) with one patch: clicking a link
(`mouse_handle_click link`) also opens plain-text **file and folder paths** under the mouse.

Upstream declined regex-based clickable regions
([kovidgoyal/kitty#3821](https://github.com/kovidgoyal/kitty/issues/3821)). This patch only
looks at the clicked line, at click time, so it costs nothing while rendering.

## What the patch does

When a click lands on no URL or OSC 8 hyperlink, kitty looks for a path at the mouse position:

- `/abs/path`, `~/path`, `./path`, `../path`, `dir/file`, `file.ext`
- an optional `:line[:col]` suffix
- relative paths resolve from the foreground program's working directory
- only paths that exist are opened

The path is opened as a `file://` URL (the line goes in the `#L12:3` fragment), so
[`open-actions.conf`](https://sw.kovidgoyal.net/kitty/open_actions/) decides which program
gets it.

To make Ctrl+click work even while a program grabs the mouse, add to `kitty.conf`:

```conf
mouse_map ctrl+left press grabbed,ungrabbed discard_event
mouse_map ctrl+left release grabbed,ungrabbed mouse_handle_click link
```

## Install (Arch / Omarchy)

```bash
./install.sh
```

It adds a `[kitty-path-click]` section at the top of `/etc/pacman.conf` and installs `kitty`,
`kitty-terminfo` and `kitty-shell-integration` from it. The package names are the stock ones,
so they replace the official packages, and `pacman -Syu` keeps them updated from this
repository because it is listed first.

Packages are built against the Omarchy stable mirror and are not signed.

## How it stays up to date

`.github/workflows/build.yml` runs every Monday. It builds when any of these changed: the
latest upstream kitty release, the kitty or Python version in the Omarchy stable mirror (a
Python bump needs a rebuild), or the patch itself. The build takes Arch's official `PKGBUILD`,
applies `path-click.patch`, and publishes the packages and the pacman database to the
[`repo` release](../../releases/tag/repo).

If the patch stops applying to a new kitty release the workflow fails, and the previous
packages stay in place.

Run it by hand with `gh workflow run build -f force=true`.

## License

The patch is a derivative of kitty and is licensed GPL-3.0-only, like kitty.
