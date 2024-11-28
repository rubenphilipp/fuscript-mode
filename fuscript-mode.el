;;; fuscript-mode.el --- A minor-mode for Blackmagic Design's Fusion-CLI/FuScript.  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  Ruben Philipp

;; Author: Ruben Philipp <me@rubenphilipp.com>
;; Keywords: tools

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

;; This minor-mode establishes a comint-process for Black Magic Design Fusion's
;; (or the version bundled with DaVinci Resolve Studio) `fuscript' CLI
;; interface.  As of now, it only supports interfacing with the Lua language, as
;; this mode is built onto the Emacs lua-mode.
;;
;; Make sure to adjust the `fuscript-program' variable to your Fusion
;; installation.
;;
;; For details on the lua-mode cf. https://immerrr.github.io/lua-mode

;;; Code:

(require 'comint)
(require 'lua-mode)


(defgroup fuscript nil
  "Minor mode for working with fuscript (lua-)code."
  :prefix "fuscript-mode-"
  :group 'fuscript-mode)

(defcustom fuscript-program
  "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fuscript"
  "The path to the fuscript command."
  :group 'fuscript
  :type 'string)

(defcustom fuscript-program-args '("-i")
  "Commandline arguments to pass to the fuscript command."
  :group 'fuscript
  :type 'list)

(defcustom fuscript-prompt-regexp "[^\n]*\\(>[\t ]+\\)+$"
  "Regexp which matches the fuscript/Lua program's prompt."
  :type  'regexp
  :group 'fuscript)

(defvar fuscript-buffer-name "fuscript")
(defvar fuscript-process-buffer nil
  "Buffer used for communication with the `fuscript' process.")
(defvar fuscript-process nil)
(defvar fuscript-process-init-code
  (mapconcat
   'identity
   '("local loadstring = loadstring or load"
     "function fuscriptmode_loadstring(str, displayname, lineoffset)"
     "  if lineoffset > 1 then"
     "    str = string.rep('\\n', lineoffset - 1) .. str"
     "  end"
     ""
     "  local x, e = loadstring(str, '@'..displayname)"
     "  if e then"
     "    error(e)"
     "  end"
     "  return x()"
     "end")
   " "))


(defun fuscript-start-process (&optional name program)
  "Run an inferior instance of `fuscript' inside Emacs."
  (interactive)
  (setq name (or name fuscript-buffer-name))
  (setq program (or program fuscript-program))
  (unless (comint-check-proc (format "*%s*" name))
    (setq fuscript-process-buffer
          (apply #'make-comint name program nil fuscript-program-args))
    (setq fuscript-process (get-buffer-process fuscript-process-buffer))
    (set-process-query-on-exit-flag fuscript-process nil)
    (with-current-buffer fuscript-process-buffer
      (require 'compile)
      (compilation-shell-minor-mode 1)
      (setq-local comint-prompt-regexp fuscript-prompt-regexp)
      ;; Don't send initialization code until seeing the prompt to ensure that
      ;; the interpreter is ready.
      (while (not (lua-prompt-line))
        (accept-process-output (get-buffer-process (current-buffer)))
        (goto-char (point-max)))
      (fuscript-send-string fuscript-process-init-code)))
  (if (called-interactively-p 'any)
      (switch-to-buffer fuscript-process-buffer)))

(defun fuscript-get-create-process ()
  "Return the active `fuscript' process and create one if necessary."
  (fuscript-start-process)
  fuscript-process)


(defun fuscript-kill-process ()
  "Kill the `fuscript' process."
  (interactive)
  (when (buffer-live-p fuscript-process-buffer)
    (kill-buffer fuscript-process-buffer)
    (setq fuscript-process-buffer nil)))

(defun fuscript-restart-process ()
  "Restart the `fuscript' process."
  (interactive)
  (fuscript-kill-process)
  (fuscript-start-process))

(defun fuscript-send-string (string)
  "Send STRING plus a newline to the `fuscript' process."
  (unless (string-equal (substring string -1) "\n")
    (setq string (concat string "\n")))
  (process-send-string (fuscript-get-create-process) string))


;; derived from lua-mode
(defun fuscript-send-region (start end)
  "Sends a region to the `fuscript' process."
  (interactive "r")
  (setq start (lua-maybe-skip-shebang-line start))
  (let* ((region-str (buffer-substring-no-properties start end))
         (lineno (line-number-at-pos start))
         (fuscript-file (or (buffer-file-name) (buffer-name)))
         (command
          ;; Print empty line before executing the code so that the first line
          ;; of output doesn't end up on the same line as current prompt.
          (format "print(''); fuscriptmode_loadstring(%s, %s, %s);\n"
                  (lua-make-lua-string region-str)
                  (lua-make-lua-string fuscript-file)
                  lineno)))
    (fuscript-send-string command)))

(defun fuscript-send-current-line ()
  "Send current line to `fuscript' process."
  (interactive)
  (fuscript-send-region (line-beginning-position) (line-end-position)))


(defun fuscript-send-buffer ()
  "Send whole buffer to `fuscript' process."
  (interactive)
  (fuscript-send-region (point-min) (point-max)))


;;;###autoload
(define-minor-mode fuscript-mode
  "Toggle fuscript-mode."
  :lighter "fuscript"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c C-l") 'fuscript-send-current-line)
            (define-key map (kbd "C-c C-r") 'fuscript-send-region)
            (define-key map (kbd "C-c C-b") 'fuscript-send-buffer)
            map))


(provide 'fuscript-mode)

;;; fuscript-mode.el ends here
