# eglot-signature-posframe

Show [eglot](https://github.com/joaotavora/eglot) signature help in a
[posframe](https://github.com/tumashu/posframe) (child frame) near point,
instead of the echo area.

## Motivation
I have been using `eglot` in many years. It is a great package, offering deep integration with many of Emacs's default behaviors. However, I have started writing Rust many times with eglot, I have encountered difficulty when writing Rust code. Packages in Rust have many, many methods and countless traits. I can not remember them or their signature while writing code.
Currently, I use `eglot` with `corfu` . It's great, but I can't see signature while writing code because it shows on eldoc. Although I know eldoc offers help documentation in the buffer rather than the echo area, but I want to see signature while writing, without having to move my focus elsewhere.

To address this, I created this package. I aimed to keep it as simple as possible, utilizing an LLM during development. 

### Disclaimer

No warranty while using this package, and this package is fully written by LLM. Please use caution and discontinue use if you have concerns regarding LLM-generated code.

## Features

- **Display signature only**
  - Only the function signature returned by the language
    server is shown. Documentation and hover help are never displayed — this
    package never touches `eglot-hover-eldoc-function`.
  - By default only the first line of the signature is shown, dropping
    verbose parameter documentation. Set
    `eglot-signature-posframe-first-line-only` to `nil` for the full output.
- **Above or below point**
  - Choose where the posframe appears relative to cursor, and flip it on the fly.
- **Auto hide**
  - When eglot reports no signature while the posframe is visible,
    the posframe is hidden automatically. It also hides when you switch buffers.

## Requirements

- Emacs 29.1+
- [posframe](https://github.com/tumashu/posframe) 1.1.0+
- [eglot](https://github.com/joaotavora/eglot) 1.15+ (bundled with Emacs 29+)

A graphical Emacs (no -nw) was tested. If childframe can run in terminal, this might be able to run in a terminal (with `-nw` option).

## Installation

Place `eglot-signature-posframe.el` on your `load-path` and:

```elisp
(require 'eglot-signature-posframe)
```

Or with `use-package` and a package manager that can fetch from Git:

```elisp
(use-package eglot-signature-posframe
  :hook (eglot-managed-mode . eglot-signature-posframe-mode))
```

Or with `elpaca` or `straight`:

```elisp
(elpaca (elpaca (key-layout-mapper :type git :host github :repo "derui/eglot-signature-posframe")))
```

## Usage

Enable the minor mode in eglot-managed buffers:

```elisp
(add-hook 'eglot-managed-mode-hook #'eglot-signature-posframe-mode)
```

As you move point inside a function call, the signature appears in a child
frame. When there is no signature, the frame disappears.

To flip the posframe between above and below point interactively:

```
M-x eglot-signature-posframe-toggle-position
```

## Customization

| Variable | Default | Description |
| --- | --- | --- |
| `eglot-signature-posframe-position` | `above` | `below` or `above` point. |
| `eglot-signature-posframe-delay` | `0.2` | Idle seconds before requesting a signature. |
| `eglot-signature-posframe-border-width` | `1` | Outer border width in pixels. |
| `eglot-signature-posframe-border-color` | `"gray50"` | Outer border color. |
| `eglot-signature-posframe-max-width` | `nil` | Max width in characters, or `nil` for no limit. |
| `eglot-signature-posframe-first-line-only` | `t` | Show only the first line of the signature, dropping verbose parameter documentation. Set to `nil` for the full multi-line signature. |
| `eglot-signature-posframe-y-pixel-offset` | `0` | Vertical offset in pixels added to the posframe position (positive moves down). |
| `eglot-signature-posframe-parameters` | `nil` | Extra frame parameters passed to `posframe-show`. |

The text uses the `eglot-signature-posframe-face` face (inherits `default` by
default), so you can restyle the foreground/background:

```elisp
(set-face-attribute 'eglot-signature-posframe-face nil
                    :background "#2d2d2d" :foreground "#dcdcdc")
```

## License

Apache Licence 2.0. See [LICENSE](LICENSE).
