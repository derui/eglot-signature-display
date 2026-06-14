;;; eglot-signature-display.el --- Show eglot signature inline near point -*- lexical-binding: t; -*-

;; Copyright (C) 2026 derui

;; Author: derui <derutakayu@gmail.com>
;; Maintainer: derui <derutakayu@gmail.com>
;; URL: https://github.com/derui/eglot-signature-display
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (eglot "1.15"))
;; Keywords: convenience, languages, tools

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `eglot-signature-display' shows the signature help provided by
;; eglot inline near point, instead of in the echo area.
;;
;; The signature is rendered as a virtual line using an overlay (a
;; `before-string' or `after-string'), not a child frame.  This means it
;; appears instantly, works in terminal frames, and has no
;; platform-specific child-frame quirks.  The cost is that the virtual
;; line displaces surrounding buffer text rather than floating over it.
;;
;; Features:
;;
;; - Only the signature is shown.  Documentation and hover help are never
;;   displayed; this package never touches `eglot-hover-eldoc-function'.
;; - The display is tied to editing a call: it appears when an edit
;;   leaves point right after a trigger character (`(' or `,', as
;;   advertised by the language server), whether you typed it or a
;;   completion expanded a call like `abc(|)' for you, and refreshes as
;;   you fill in the arguments.  Ordinary navigation does not bring it
;;   up.  `eglot-signature-display-show' requests it on demand and
;;   `eglot-signature-display-hide' (or C-g) dismisses it.
;; - The signature can be shown either above or below point.  Use
;;   `eglot-signature-display-position' to set the default, or
;;   `eglot-signature-display-toggle-position' to flip it interactively.
;; - When eglot reports no signature, e.g. once you leave the call, the
;;   inline display is hidden automatically.
;;
;; Usage:
;;
;;   (add-hook 'eglot-managed-mode-hook #'eglot-signature-display-mode)

;;; Code:

(require 'eglot)

(defgroup eglot-signature-display nil
  "Show eglot signature help inline near point."
  :group 'eglot
  :prefix "eglot-signature-display-")

(defcustom eglot-signature-display-position 'above
  "Where the signature is shown relative to point.
Either the symbol `below' (under point) or `above' (over point)."
  :type
  '(choice (const :tag "Below point" below)
           (const :tag "Above point" above))
  :group 'eglot-signature-display)

(defcustom eglot-signature-display-delay 0.2
  "Idle time in seconds before requesting signature help.
A request is only sent after Emacs has been idle this long, to avoid
flooding the language server while typing."
  :type 'number
  :group 'eglot-signature-display)

(defcustom eglot-signature-display-border-width 1
  "Width in pixels of the box drawn around the signature.
A value of 0 disables the box."
  :type 'integer
  :group 'eglot-signature-display)

(defcustom eglot-signature-display-border-color "gray50"
  "Color of the box drawn around the signature."
  :type 'string
  :group 'eglot-signature-display)

(defcustom eglot-signature-display-max-width nil
  "Maximum width of the signature in characters, or nil for no limit.
Lines longer than this are truncated with an ellipsis."
  :type '(choice (const :tag "No limit" nil) integer)
  :group 'eglot-signature-display)

(defcustom eglot-signature-display-first-line-only t
  "When non-nil, show only the first line of the signature.
Eldoc may report a verbose, multi-line signature that includes
parameter documentation.  With this enabled only the first line,
which is the signature itself, is displayed."
  :type 'boolean
  :group 'eglot-signature-display)

(defcustom eglot-signature-display-extra-trigger-characters nil
  "Extra characters, as strings, that activate the signature display.
These are added to the trigger characters advertised by the language
server (typically \"(\" and \",\").  For example, add \"<\" to also
trigger on generic argument lists."
  :type '(repeat string)
  :group 'eglot-signature-display)

(defvar-local eglot-signature-display--timer nil
  "Idle timer scheduling the next signature request.")

(defvar-local eglot-signature-display--overlay nil
  "Overlay carrying the inline signature, or nil when hidden.")

(defvar-local eglot-signature-display--signature-key nil
  "Signature text, stripped of properties, of the current overlay.
Used to detect when the signature changes: while it is unchanged the
overlay keeps its position instead of following point.")

(defvar-local eglot-signature-display--indent ""
  "Leading indent applied when the overlay was last anchored.
Remembered so refreshes keep the column where the signature first
appeared instead of jumping to point's current column.")

(defvar-local eglot-signature-display--tick nil
  "Value of `buffer-chars-modified-tick' after the last command.
Compared on each command to tell whether the buffer was edited, so a
completion that inserts a call like \"abc(|)\" activates the display the
same way typing the trigger character does.")

(defvar-local eglot-signature-display--active nil
  "Non-nil while a signature is being tracked for the current call.
Set when a trigger character is typed (or the signature is requested
manually) and cleared when the display is hidden.  While it is non-nil
the display refreshes as you edit so the active-argument highlight keeps
up; while it is nil ordinary navigation does not request a signature.")

;;; Rendering

(defun eglot-signature-display--box ()
  "Return a face spec drawing the configured box, or nil when disabled.
A negative `:line-width' draws the box inside the character cells so the
virtual line keeps the same height as real text."
  (when (> eglot-signature-display-border-width 0)
    `(:box
      (:line-width
       ,(- eglot-signature-display-border-width)
       :color ,eglot-signature-display-border-color))))

(defun eglot-signature-display--render (string)
  "Return STRING truncated to the max width, with the box face merged in.
The signature's own faces, such as eglot's highlight of the active
argument, are preserved; the box is appended without overriding them."
  (let*
      ((width eglot-signature-display-max-width)
       (lines (split-string string "\n"))
       (lines
        (if width
            (mapcar
             (lambda (line)
               (truncate-string-to-width line width nil nil t))
             lines)
          lines))
       ;; `split-string'/`string-join' yield a fresh string, so the
       ;; in-place `add-face-text-property' never mutates the original.
       (text (string-join lines "\n"))
       (box (eglot-signature-display--box)))
    (when box
      (add-face-text-property 0 (length text) box t text))
    text))

;;; Showing and hiding

(defun eglot-signature-display--show (string)
  "Show STRING inline near point as a virtual line.
A single overlay is reused.  It is re-anchored to point, and indented to
point's column, only when the signature text changes; while the same
signature stays active the overlay keeps its position and just refreshes
its content so the active-argument highlight still updates.  Whether the
signature appears above or below is controlled by
`eglot-signature-display-position'."
  (let* ((rendered (eglot-signature-display--render string))
         (above (eq eglot-signature-display-position 'above))
         (key (substring-no-properties string))
         (ov eglot-signature-display--overlay)
         (same
          (and (overlayp ov)
               (overlay-buffer ov)
               (equal key eglot-signature-display--signature-key))))
    (unless same
      (let ((pos
             (if above
                 (line-beginning-position)
               (line-end-position))))
        (unless (overlayp ov)
          (setq ov (make-overlay pos pos))
          (setq eglot-signature-display--overlay ov))
        (move-overlay ov pos pos (current-buffer)))
      (setq
       eglot-signature-display--signature-key key
       eglot-signature-display--indent (make-string (current-column) ?\s)))
    (let ((indent eglot-signature-display--indent))
      (overlay-put ov 'before-string nil)
      (overlay-put ov 'after-string nil)
      (if above
          (overlay-put
           ov 'before-string (concat indent rendered "\n"))
        (overlay-put
         ov 'after-string (concat "\n" indent rendered))))))

(defun eglot-signature-display--hide ()
  "Hide the inline signature if it is visible."
  (when (overlayp eglot-signature-display--overlay)
    (delete-overlay eglot-signature-display--overlay))
  (setq
   eglot-signature-display--overlay nil
   eglot-signature-display--signature-key nil
   eglot-signature-display--active nil))

;;; Requesting signatures

(defun eglot-signature-display--callback (string &rest _)
  "Display STRING inline, or hide the display when STRING is empty.
Used as the callback for `eglot-signature-eldoc-function'."
  (if (and (stringp string) (> (length string) 0))
      (eglot-signature-display--show
       (if eglot-signature-display-first-line-only
           (car (split-string string "\n"))
         string))
    (eglot-signature-display--hide)))

(defun eglot-signature-display--request (buffer)
  "Request signature help for BUFFER and update the inline display."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (if (and (bound-and-true-p eglot-signature-display-mode)
               (eglot-managed-p)
               (eglot-server-capable :signatureHelpProvider))
          ;; `eglot-signature-eldoc-function' performs the request
          ;; asynchronously and calls our callback with the signature
          ;; string, or nil when there is none (which hides the display).
          (eglot-signature-eldoc-function
           #'eglot-signature-display--callback)
        (eglot-signature-display--hide)))))

(defun eglot-signature-display--schedule ()
  "Schedule a signature request after `eglot-signature-display-delay'."
  (when (timerp eglot-signature-display--timer)
    (cancel-timer eglot-signature-display--timer))
  (setq eglot-signature-display--timer
        (run-with-idle-timer eglot-signature-display-delay
                             nil
                             #'eglot-signature-display--request
                             (current-buffer))))

;;; Triggering

(defun eglot-signature-display--trigger-characters ()
  "Return the characters that activate the signature display, as strings.
These are the trigger characters advertised by the language server plus
`eglot-signature-display-extra-trigger-characters'."
  (let ((opts (eglot-server-capable :signatureHelpProvider)))
    ;; `:triggerCharacters' is a vector of single-character strings;
    ;; `append' coerces it to a list.  When the server advertised no
    ;; options (a bare t) `plist-get' on it yields nil.
    (append
     (and (listp opts) (plist-get opts :triggerCharacters))
     eglot-signature-display-extra-trigger-characters
     nil)))

(defun eglot-signature-display--activate-p (modified)
  "Non-nil when the current command should open the signature display.
MODIFIED is non-nil when the command edited the buffer.  Activation
happens when an edit leaves point right after a trigger character: this
covers typing `(' or `,' directly, and completion expanding a call such
as \"abc(|)\" where the trigger character was inserted for you rather
than typed."
  (and modified
       (let ((before (char-before)))
         (and before
              (member
               (char-to-string before)
               (eglot-signature-display--trigger-characters))))))

(defun eglot-signature-display--post-command ()
  "Decide whether to request a signature after the current command.
A signature is requested only when an edit just opened a call, or while
one is already active so the display keeps up with editing.  Ordinary
navigation outside a call requests nothing."
  (let* ((tick (buffer-chars-modified-tick))
         (modified (not (eql tick eglot-signature-display--tick))))
    (setq eglot-signature-display--tick tick)
    (cond
     ((memq
       this-command '(keyboard-quit eglot-signature-display-hide))
      (eglot-signature-display--hide))
     ((eglot-signature-display--activate-p modified)
      (setq eglot-signature-display--active t)
      (eglot-signature-display--schedule))
     (eglot-signature-display--active
      (eglot-signature-display--schedule)))))

;;; Commands

;;;###autoload
(defun eglot-signature-display-show ()
  "Request and show the signature at point, regardless of trigger state.
Use this to bring up the signature on demand, e.g. when point is already
inside a call you did not just type."
  (interactive)
  (setq eglot-signature-display--active t)
  (eglot-signature-display--request (current-buffer)))

;;;###autoload
(defun eglot-signature-display-hide ()
  "Hide the inline signature."
  (interactive)
  (eglot-signature-display--hide))

;;;###autoload
(defun eglot-signature-display-toggle-position ()
  "Toggle between showing the signature above and below point."
  (interactive)
  (setq eglot-signature-display-position
        (if (eq eglot-signature-display-position 'above)
            'below
          'above))
  (message "eglot-signature-display: showing %s point"
           eglot-signature-display-position))

;;; Minor mode

;;;###autoload
(define-minor-mode eglot-signature-display-mode
  "Toggle showing eglot signature help inline near point.

When enabled, signature help from eglot is shown as a virtual line
near point instead of the echo area.  Only the signature is shown;
documentation and hover help are not.  The display hides itself
automatically when there is no signature to show.

This mode is intended to be enabled in eglot-managed buffers, e.g.:

  (add-hook \\='eglot-managed-mode-hook #\\='eglot-signature-display-mode)"
  :lighter " SigPos"
  :group
  'eglot-signature-display
  (if eglot-signature-display-mode
      (progn
        (setq eglot-signature-display--tick
              (buffer-chars-modified-tick))
        (add-hook
         'post-command-hook #'eglot-signature-display--post-command
         nil t))
    (remove-hook
     'post-command-hook #'eglot-signature-display--post-command
     t)
    (when (timerp eglot-signature-display--timer)
      (cancel-timer eglot-signature-display--timer)
      (setq eglot-signature-display--timer nil))
    (eglot-signature-display--hide)))

(provide 'eglot-signature-display)
;;; eglot-signature-display.el ends here
