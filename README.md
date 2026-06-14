# eglot-signature-display

Show [eglot](https://github.com/joaotavora/eglot) signature help inline near
point, instead of the echo area. The signature is rendered as a virtual line
using an overlay, so it appears instantly and works in terminal frames.

## Motivation
I have been using `eglot` in many years. It is a great package, offering deep integration with many of Emacs's default behaviors. However, I have started writing Rust many times with eglot, I have encountered difficulty when writing Rust code. Packages in Rust have many, many methods and countless traits. I can not remember them or their signature while writing code.
Currently, I use `eglot` with `corfu` . It's great, but I can't see signature while writing code because it shows on eldoc. Although I know eldoc offers help documentation in the buffer rather than the echo area, but I want to see signature while writing, without having to move my focus elsewhere.

To address this, I created this package. I aimed to keep it as simple as possible, utilizing an LLM during development. 

### Disclaimer

No warranty while using this package, and this package is fully written by LLM. Please use caution and discontinue use if you have concerns regarding LLM-generated code.

## Features

- **Shows while you edit a call**
  - The signature appears when an edit leaves point right after a trigger
    character (`(` or `,`, as advertised by the language server) — whether
    you typed it or a completion expanded a call like `abc(|)` for you — and
    refreshes as you fill in the arguments, so the active-parameter highlight
    keeps up. Ordinary navigation does not bring it up.
  - `M-x eglot-signature-display-show` requests it on demand (e.g. when
    point is already inside a call); `M-x eglot-signature-display-hide` (or
    `C-g`) dismisses it.
- **Display signature only**
  - Only the function signature returned by the language
    server is shown. Documentation and hover help are never displayed — this
    package never touches `eglot-hover-eldoc-function`.
  - By default only the first line of the signature is shown, dropping
    verbose parameter documentation. Set
    `eglot-signature-display-first-line-only` to `nil` for the full output.
- **Above or below point**
  - Choose where the signature appears relative to cursor, and flip it on the fly.
- **Auto hide**
  - When eglot reports no signature — for example once you leave the call —
    the inline display is hidden automatically. It also hides when you switch
    buffers.

## Screenshot
![Screenshot](./screenshot/screenshot.png)

## Requirements

- Emacs 29.1+
- [eglot](https://github.com/joaotavora/eglot) 1.15+ (bundled with Emacs 29+)

The signature is drawn as an overlay (a virtual line), not a child frame, so
it works in both graphical and terminal (`-nw`) frames with no extra
dependency.

## Installation

Place `eglot-signature-display.el` on your `load-path` and:

```elisp
(require 'eglot-signature-display)
```

Or with `use-package` and a package manager that can fetch from Git:

```elisp
(use-package eglot-signature-display
  :hook (eglot-managed-mode . eglot-signature-display-mode))
```

Or with `elpaca` or `straight`:

```elisp
(elpaca (elpaca (key-layout-mapper :type git :host github :repo "derui/eglot-signature-display")))
```

## Usage

Enable the minor mode in eglot-managed buffers:

```elisp
(add-hook 'eglot-managed-mode-hook #'eglot-signature-display-mode)
```

As you type the arguments of a function call, the signature appears inline
near point. When you leave the call, it disappears. To bring it up on demand,
run `M-x eglot-signature-display-show`; to dismiss it, `M-x
eglot-signature-display-hide` (or `C-g`).

To flip the signature between above and below point interactively:

```
M-x eglot-signature-display-toggle-position
```

## Customization

| Variable | Default | Description |
| --- | --- | --- |
| `eglot-signature-display-position` | `above` | `below` or `above` point. |
| `eglot-signature-display-delay` | `0.2` | Idle seconds before requesting a signature. |
| `eglot-signature-display-border-width` | `1` | Box border width in pixels. `0` disables the box. |
| `eglot-signature-display-border-color` | `"gray50"` | Box border color. |
| `eglot-signature-display-max-width` | `nil` | Max width in characters, or `nil` for no limit. |
| `eglot-signature-display-first-line-only` | `t` | Show only the first line of the signature, dropping verbose parameter documentation. Set to `nil` for the full multi-line signature. |
| `eglot-signature-display-extra-trigger-characters` | `nil` | Extra characters (as strings) that activate the display, added to the server's trigger characters. |

## License

Apache Licence 2.0. See [LICENSE](LICENSE).
