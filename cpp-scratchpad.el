;;; cpp-scratchpad.el -- Scratchpad for C++  -*- lexical-binding: t -*-

;; Copyright (C) 2018 Jakub Wojeciech

;; Author: Jakub Wojciech <jakub-w@riseup.net>
;; Maintainer:
;; Created:
;; Version:
;; Keywords: c tools
;; Package-Requires:
;; URL: https://github.com/jakub-w/cpp-scratchpad

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file LICENSE.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; The `cpp-scratchpad' package provides simple and quick method to open
;; a scratchpad for testing code or prototyping in C++.
;;
;; The simplest way to use it is to add the package to `load-path' or
;; putting (require 'cpp-scratchpad) in an init file.
;; Then you can call `cpp-scratchpad-new' to create new, empty scratchpad.
;;
;; To compile the code and run it, press C-c C-c
;; To compile without running: C-u C-c C-c
;;
;; To close the scratchpad just kill the buffer. Its compilation buffer will
;; be killed alongside.
;;
;; The template for a scratchpad is stored in the directory specified by
;; `cpp-scratchpad-template-path' variable.
;; The main.cpp file should include an indicator where to put a point after
;; creating a new scratchpad. The indicator is a char: '`' (backquote).

;;; Code:

(defvar cpp-scratchpad-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'cpp-scratchpad-compile)
    map)
  "A key map for `cpp-scratchpad-mode'.")

;; TODO: Add usage documentation inside this minor mode doc.
;; TODO: Create a simple way to add linker flags to the compilation.
;;       It would probably help if the whole build-system system were thrown
;;       out and compile_commands.json would be generated by cpp-scratchpad.el
;;       itself.
(define-minor-mode
  cpp-scratchpad-mode
  "A minor mode used inside of cpp-scratchpad buffer. It's not designed to be
used anywhere else.

The following keys are available in `cpp-scratchpad-mode':

\\{cpp-scratchpad-mode-map}"
  nil
  " cpp-s"
  'cpp-scratchpad-mode-map
  (add-hook 'kill-buffer-query-functions #'cpp-scratchpad-kill-buffer-function
	    nil t)
  (message "Press C-c C-c to compile and run your code"))

(defcustom cpp-scratchpad-scratch-dir
  (concat (temporary-file-directory) "cpp-scratchpad/")
  "Directory where the files for a scratch will be created.

The directory should be in a place that allows the execution of
binary files."
  :type '(directory)
  :group 'cpp-scratchpad)

(defcustom cpp-scratchpad-template-path
  (concat (file-name-directory (locate-library "cpp-scratchpad"))
	  "cpp-scratch-template/")
  "Path to a scratchpad template directory."
  :type '(directory)
  :group 'cpp-scratchpad)

(defcustom cpp-scratchpad-build-system-list
  '(("meson"
	   :builddir-gen-command "meson builddir"
	   :compile-command "cd builddir && ninja"
	   :signature-file "ninja.build")
    ("cmake"
           :builddir-gen-command "mkdir builddir && cd builddir && \
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=YES .."
	   :compile-command "cd builddir && make"
	   :signature-file "CMakeCache.txt"))
  "List containing build system information.

Car of every element is an executable name of the build system (without
the path part). Cdr is a property list with the rest of information.

:builddir-gen-command - Command to generate the build directory.

:compile-command - Command to call after the build system has prepared all
                   necessary files.

:signature-file - Name of the file in build directory that is unique to the
                  build system."
  :type '(alist :key-type string :value-type (plist :value-type string))
  :group 'cpp-scratchpad)

(defcustom cpp-scratchpad-build-system
  (seq-some (lambda (tool)
	      (when (executable-find (car tool))
		(car tool)))
	    cpp-scratchpad-build-system-list)
  "Build system chosen to build a scratchpad.

It defaults to whatever tool listed in `cpp-scratchpad-build-system-list'
is found on a system. Priority can be changed by modifying said list.

This variable is global and shouldn't be used as buffer-local."
  :type '(string)
  :group 'cpp-scratchpad)

(defvar cpp-scratchpad-current-path nil
  "Path to current temporary scratchpad directory.")
(make-variable-buffer-local 'cpp-scratchpad-current-path)

(defvar cpp-scratchpad-compilation-buffer nil
  "Buffer used as an output to compilation current scratchpad.")
(make-variable-buffer-local 'cpp-scratchpad-compilation-buffer)

(defvar cpp-scratchpad-before-compile-hook nil
  "List of functions called with no args before compiling cpp-scratchpad
buffer. Functions are called after killing and recreating the
compilation buffer, just before the compilation.")

(defvar cpp-scratchpad-before-kill-hook nil
  "List of functions called with no args before killing cpp-scratchpad
buffer.")

(defun cpp-scratchpad-kill-buffer-function ()
  (when cpp-scratchpad-mode
    (run-hooks 'cpp-scratchpad-before-kill-hook)
    (when (buffer-live-p cpp-scratchpad-compilation-buffer)
      (kill-buffer cpp-scratchpad-compilation-buffer))
    (delete-directory cpp-scratchpad-current-path t)
    (set-buffer-modified-p nil))
  t)

(defun cpp-scratchpad--get-tool-prop (tool property)
  (plist-get (cdr (assoc tool cpp-scratchpad-build-system-list)) property))

(defun cpp-scratchpad-template-setup ()
  "Set up template directory.

Check if there is no template set up or if build systems or compilers have
changed and update the template if necessary."
  (interactive)
  nil)

(defun cpp-scratchpad--regenerate-build-files ()
  "Regenerate the files used to build a scratchpad."
  (assert cpp-scratchpad-current-path)
  (delete-directory (concat cpp-scratchpad-current-path "/builddir") t)
  ;; call the build system to create builddir
  (call-process shell-file-name nil nil nil shell-command-switch
		(format "cd %s && %s"
			cpp-scratchpad-current-path
			(cpp-scratchpad--get-tool-prop
			 cpp-scratchpad-build-system :builddir-gen-command)))
  (make-symbolic-link "builddir/compile_commands.json"
		      (concat cpp-scratchpad-current-path
			      "/compile_commands.json")
		      t))

(defun cpp-scratchpad-compile (&optional dont-run)
  "Compile using Meson or Cmake build systems and then execute.

With a prefix argument \\[universal-argument], just compile without executing.

Meson has priority but it can be redefined by rearranging
`cpp-scratchpad-build-system-list'."
  (interactive "P")
  ;; TODO: fix cpp-scratchpad--build-system-matches-files-p function
  ;;       to work in current dir, not a template dir
  ;; (unless (cpp-scratchpad--build-system-matches-files-p)
  ;;   (error "Build system changed. Please, create new scratchpad."))
  (unless cpp-scratchpad-mode
    (user-error "[cpp-scratchpad] Not in the scratchpad."))
  (when (buffer-live-p cpp-scratchpad-compilation-buffer)
    (kill-buffer cpp-scratchpad-compilation-buffer))
  (setq-local cpp-scratchpad-compilation-buffer
	      (get-buffer-create
	       (save-match-data
		 (string-match "\\*\\(<[[:digit:]]+>\\)?$" (buffer-name))
		 (concat (replace-match "" nil nil (buffer-name))
			 "-result"
			 (match-string 0 (buffer-name))))))
  (save-buffer)
  (run-hooks cpp-scratchpad-before-compile-hook)
  ;; don't run if dont-run set or if didn't compile for some reason
  (if (and (not dont-run)
	   (cpp-scratchpad--build
	    cpp-scratchpad-build-system))
      (with-current-buffer cpp-scratchpad-compilation-buffer
	(progn
	  (eshell-mode)
	  (insert "cd builddir && ./scratchpad")
	  (eshell-send-input)))
    ;; on compilation errors or dont-run change to compilation-mode
    (with-current-buffer cpp-scratchpad-compilation-buffer
      (compilation-mode)))
  (pop-to-buffer cpp-scratchpad-compilation-buffer))

(defun cpp-scratchpad--build (&optional build-system)
  "Call a BUILD-SYSTEM to compile current scratchpad.

If BUILD-SYSTEM is not specified, use `cpp-scratchpad-build-system'.

Uses buffer-local `cpp-scratchpad-compilation-buffer'."
  (assert (buffer-live-p cpp-scratchpad-compilation-buffer))
  (if (eq 0 (call-process
	     shell-file-name nil cpp-scratchpad-compilation-buffer nil
  	     shell-command-switch
  	     (concat "cd " cpp-scratchpad-current-path " && "
  		     (cpp-scratchpad--get-tool-prop
		      (or build-system cpp-scratchpad-build-system)
		      :compile-command))))
      t
    nil))

(defun cpp-scratchpad--build-system-matches-files-p ()
  "Check if current build system matches files in template directory."
  (file-exists-p (concat cpp-scratchpad-template-path "/builddir/"
			 (cpp-scratchpad--get-tool-prop
			  cpp-scratchpad-build-system
			  :signature-file))))

;;;###autoload
(defun cpp-scratchpad-new ()
  "Create a new, clean C++ scratchpad and pop to it."
  (interactive)
  (catch 'err
    (unless (file-exists-p cpp-scratchpad-template-path)
      (throw 'err "[cpp-scratchpad] Scratchpad template does not exist!"))
    (let ((scratch-path
	   (progn
	     (unless (file-exists-p cpp-scratchpad-scratch-dir)
	       (make-directory cpp-scratchpad-scratch-dir t))
	     (concat (make-temp-file cpp-scratchpad-scratch-dir t) "/"))))
      ;; ;; check if build system changed and regenerate files if so
      ;; (unless (cpp-scratchpad--build-system-matches-files-p)
      ;; 	(cpp-scratchpad--regenerate-build-files))
      (copy-directory cpp-scratchpad-template-path
		      scratch-path
		      nil nil t)
      (find-file-other-window (concat scratch-path
				      "main.cpp"))
      (rename-buffer (generate-new-buffer-name "*cpp-scratchpad*"))
      (unless (search-forward "`" nil t)
	(error "[cpp-scratchpad] Template's main.cpp file doesn't contain the marker for point position"))
      (delete-char -1)
      (c-indent-line)
      (setq-local cpp-scratchpad-current-path scratch-path)
      (cpp-scratchpad--regenerate-build-files)
      (cpp-scratchpad-mode 1))))

(provide 'cpp-scratchpad)
;;; cpp-scratchpad.el ends here
