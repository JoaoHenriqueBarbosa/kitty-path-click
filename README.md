# kitty-path-click

[kitty](https://github.com/kovidgoyal/kitty) with one patch: file and folder paths matched
by `detect_url_regex` are highlighted on hover and clickable **only when they exist**, and
they open through the normal `file://` rules of `open-actions.conf`.

kitty 0.51 added `detect_url_regex`, which turns any regex match into a clickable region.
A regex loose enough to catch paths also catches `v1.5.2` or `example.com`, so stock kitty
underlines text that then opens nothing. With this patch an underline means it will open.

## What the patch does

For text matched by `detect_url_regex` that looks like a path (it has a `/`, a `.` or starts
with `~`, and no URL scheme):

- it is accepted only if the path exists; relative paths resolve from the foreground
  program's working directory, `~` is expanded, a `:line[:col]` suffix is ignored for the check
- on click it opens as `file:///abs/path#L12:3`, so the `protocol file` rules in
  [`open-actions.conf`](https://sw.kovidgoyal.net/kitty/open_actions/) pick the program

Matches that do not look like paths (issue ids and so on) behave as in stock kitty.

## Configuration

`kitty.conf`:

```conf
# Paths: /abs ~/x ./x ../x, dir/file, file.ext, each with an optional :line:col
detect_url_regex (~|\.{1,2})?/[[:alnum:]_.@%+~/-]*[[:alnum:]_@%+~/-](:[0-9]+(:[0-9]+)?)?
detect_url_regex [[:alnum:]_@%+~-][[:alnum:]_.@%+~-]*(/[[:alnum:]_.@%+~-]+)+/?(:[0-9]+(:[0-9]+)?)?
detect_url_regex [[:alnum:]_@%+~-]+\.[[:alpha:]][[:alnum:]_]{0,7}(:[0-9]+(:[0-9]+)?)?

# Optional: open links with Ctrl+click only, also while a program grabs the mouse
mouse_map left click ungrabbed mouse_handle_click selection prompt
mouse_map ctrl+left press grabbed,ungrabbed discard_event
mouse_map ctrl+left release grabbed,ungrabbed mouse_handle_click link
```

kitty underlines a link only while the held modifiers would open it, so with the mapping
above the underline shows while Ctrl is held.

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
