# gp_keypad — build instructions

`gp_keypad` is a small SDL1.2 app that renders a proper phone-style PIN
keypad (1-9 in a 3x3 grid, 0 centered below). It replaces the old
vertical 10-button list rendered by `prompt`.

## Exit codes

- `0` to `9` — digit selected
- `255`     — cancelled (B button or MENU)

## Arguments

```
gp_keypad "<title>" "<message>"
```

`<message>` may contain one `\n` to render a second, dimmer line.

## Building for Miyoo Mini (Onion OS)

The easiest way is the official
[union-miyoomini-toolchain](https://github.com/shauninman/union-miyoomini-toolchain)
docker image:

```sh
# From the ParentalControl folder
docker run --rm -it -v "$PWD":/root/workspace \
    ghcr.io/shauninman/union-miyoomini-toolchain \
    make -C /root/workspace/src
```

The binary is produced at `bin/gp_keypad`. Commit it (or ship it alongside
the install) and the shell scripts will detect and use it automatically.

## Fallback

If `bin/gp_keypad` is missing or not executable, both `parental_ui.sh` and
`parental_hook.sh` silently fall back to the old 10-button `prompt` menu —
so the app keeps working without the binary.
