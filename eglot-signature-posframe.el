;;; eglot-signature-posframe.el --- Show eglot signature in a posframe -*- lexical-binding: t; -*-

;; Copyright (C) 2026 derui

;; Author: derui <derutakayu@gmail.com>
;; Maintainer: derui <derutakayu@gmail.com>
;; URL: https://github.com/derui/eglot-signature-posframe
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (posframe "1.1.0") (eglot "1.15"))
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

;; `eglot-signature-posframe' shows the signature help provided by
;; eglot in a child frame (posframe) near point, instead of in the echo
;; area.
;;
;; Features:
;;
;; - Only the signature is shown.  Documentation and hover help are never
;;   displayed; this package never touches `eglot-hover-eldoc-function'.
;; - The posframe can be displayed either above or below point.  Use
;;   `eglot-signature-posframe-position' to set the default, or
;;   `eglot-signature-posframe-toggle-position' to flip it interactively.
;; - When eglot reports no signature while a posframe is visible, the
;;   posframe is hidden automatically.
;;
;; Usage:
;;
;;   (add-hook 'eglot-managed-mode-hook #'eglot-signature-posframe-mode)

;;; Code:

(require 'posframe)
(require 'eglot)

(defgroup eglot-signature-posframe nil
  "Show eglot signature help in a posframe."
  :group 'eglot
  :prefix "eglot-signature-posframe-")

(defcustom eglot-signature-posframe-position 'above
  "Where the posframe is shown relative to point.
Either the symbol `below' (under point) or `above' (over point)."
  :type
  '(choice (const :tag "Below point" below)
           (const :tag "Above point" above))
  :group 'eglot-signature-posframe)

(defcustom eglot-signature-posframe-delay 0.2
  "Idle time in seconds before requesting signature help.
A request is only sent after Emacs has been idle this long, to avoid
flooding the language server while typing."
  :type 'number
  :group 'eglot-signature-posframe)

(defcustom eglot-signature-posframe-border-width 8
  "Width in pixels of the posframe's internal border."
  :type 'integer
  :group 'eglot-signature-posframe)

(defcustom eglot-signature-posframe-border-color "transparent"
  "Color of the posframe's internal border."
  :type 'string
  :group 'eglot-signature-posframe)

(defcustom eglot-signature-posframe-outer-border-width 1
  "Width in pixels of the posframe's outer border."
  :type 'integer
  :group 'eglot-signature-posframe)

(defcustom eglot-signature-posframe-outer-border-color "gray50"
  "Color of the posframe's outer border."
  :type 'string
  :group 'eglot-signature-posframe)

(defcustom eglot-signature-posframe-max-width nil
  "Maximum width of the posframe in characters, or nil for no limit."
  :type '(choice (const :tag "No limit" nil) integer)
  :group 'eglot-signature-posframe)

(defcustom eglot-signature-posframe-first-line-only t
  "When non-nil, show only the first line of the signature.
Eldoc may report a verbose, multi-line signature that includes
parameter documentation.  With this enabled only the first line,
which is the signature itself, is displayed."
  :type 'boolean
  :group 'eglot-signature-posframe)

(defcustom eglot-signature-posframe-parameters nil
  "Extra frame parameters passed to `posframe-show'."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'eglot-signature-posframe)

(defcustom eglot-signature-posframe-y-pixel-offset 0
  "Vertical offset in pixels added to the posframe position.
Positive values move the posframe downward."
  :type 'integer
  :group 'eglot-signature-posframe)

(defface eglot-signature-posframe-face '((t :inherit default))
  "Face used for the text shown in the signature posframe."
  :group 'eglot-signature-posframe)

(defconst eglot-signature-posframe--buffer
  " *eglot-signature-posframe*"
  "Name of the buffer backing the signature posframe.")

(defvar-local eglot-signature-posframe--timer nil
  "Idle timer scheduling the next signature request.")

(defvar-local eglot-signature-posframe--frame nil
  "The child frame returned by the last `posframe-show' call, or nil.")

;;; Position handlers

(defun eglot-signature-posframe--poshandler ()
  "Return the poshandler matching `eglot-signature-posframe-position'.
These built-in posframe handlers resolve the integer point in
INFO's `:position' through `posn-at-point' themselves."
  (if (eq eglot-signature-posframe-position 'above)
      #'posframe-poshandler-point-bottom-left-corner-upward
    #'posframe-poshandler-point-bottom-left-corner))

;;; Showing and hiding

(defun eglot-signature-posframe--frame-visible-p ()
  "Return non-nil when the signature posframe is currently visible."
  (and eglot-signature-posframe--frame
       (frame-live-p eglot-signature-posframe--frame)
       (frame-visible-p eglot-signature-posframe--frame)))

(defun eglot-signature-posframe--show (string)
  "Show STRING in the signature posframe near point.
If the posframe is already visible, only the buffer content is updated so
the frame does not move while the user types within the same call.
Otherwise a new posframe is created at the current point."
  (when (posframe-workable-p)
    (if (eglot-signature-posframe--frame-visible-p)
        (with-current-buffer (get-buffer-create
                              eglot-signature-posframe--buffer)
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert string)))
      (setq
       eglot-signature-posframe--frame
       (posframe-show
        eglot-signature-posframe--buffer
        :string string
        :position (point)
        :poshandler (eglot-signature-posframe--poshandler)
        :y-pixel-offset eglot-signature-posframe-y-pixel-offset
        :foreground-color
        (face-foreground 'eglot-signature-posframe-face nil t)
        :background-color
        (face-background 'eglot-signature-posframe-face nil t)
        :internal-border-width eglot-signature-posframe-border-width
        :internal-border-color eglot-signature-posframe-border-color
        :border-width eglot-signature-posframe-outer-border-width
        :border-color eglot-signature-posframe-outer-border-color
        :max-width eglot-signature-posframe-max-width
        :accept-focus nil
        :hidehandler #'posframe-hidehandler-when-buffer-switch
        :override-parameters eglot-signature-posframe-parameters)))))

(defun eglot-signature-posframe--hide ()
  "Hide the signature posframe if it is visible."
  (setq eglot-signature-posframe--frame nil)
  (posframe-hide eglot-signature-posframe--buffer))

;;; Requesting signatures

(defun eglot-signature-posframe--callback (string &rest _)
  "Display STRING in the posframe, or hide it when STRING is empty.
Used as the callback for `eglot-signature-eldoc-function'."
  (if (and (stringp string) (> (length string) 0))
      (eglot-signature-posframe--show
       (if eglot-signature-posframe-first-line-only
           (car (split-string string "\n"))
         string))
    (eglot-signature-posframe--hide)))

(defun eglot-signature-posframe--request (buffer)
  "Request signature help for BUFFER and update the posframe."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (if (and (bound-and-true-p eglot-signature-posframe-mode)
               (eglot-managed-p)
               (eglot-server-capable :signatureHelpProvider))
          ;; `eglot-signature-eldoc-function' performs the request
          ;; asynchronously and calls our callback with the signature
          ;; string, or nil when there is none (which hides the posframe).
          (eglot-signature-eldoc-function
           #'eglot-signature-posframe--callback)
        (eglot-signature-posframe--hide)))))

(defun eglot-signature-posframe--schedule ()
  "Schedule a signature request after `eglot-signature-posframe-delay'."
  (when (timerp eglot-signature-posframe--timer)
    (cancel-timer eglot-signature-posframe--timer))
  (setq eglot-signature-posframe--timer
        (run-with-idle-timer eglot-signature-posframe-delay
                             nil
                             #'eglot-signature-posframe--request
                             (current-buffer))))

;;; Commands

;;;###autoload
(defun eglot-signature-posframe-toggle-position ()
  "Toggle between showing the signature posframe above and below point."
  (interactive)
  (setq eglot-signature-posframe-position
        (if (eq eglot-signature-posframe-position 'above)
            'below
          'above))
  (message "eglot-signature-posframe: showing %s point"
           eglot-signature-posframe-position))

;;; Minor mode

;;;###autoload
(define-minor-mode eglot-signature-posframe-mode
  "Toggle showing eglot signature help in a posframe.

When enabled, signature help from eglot is shown in a child frame
near point instead of the echo area.  Only the signature is shown;
documentation and hover help are not.  The posframe hides itself
automatically when there is no signature to show.

This mode is intended to be enabled in eglot-managed buffers, e.g.:

  (add-hook \\='eglot-managed-mode-hook #\\='eglot-signature-posframe-mode)"
  :lighter " SigPos"
  :group
  'eglot-signature-posframe
  (if eglot-signature-posframe-mode
      (add-hook
       'post-command-hook #'eglot-signature-posframe--schedule
       nil t)
    (remove-hook
     'post-command-hook #'eglot-signature-posframe--schedule
     t)
    (when (timerp eglot-signature-posframe--timer)
      (cancel-timer eglot-signature-posframe--timer)
      (setq eglot-signature-posframe--timer nil))
    (eglot-signature-posframe--hide)))

(provide 'eglot-signature-posframe)
;;; eglot-signature-posframe.el ends here
