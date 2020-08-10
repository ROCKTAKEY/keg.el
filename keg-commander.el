;;; keg-commander.el --- Emacs command line parser

;; Copyright (C) 2013 Johan Andersson

;; Author: Johan Andersson <johan.rejeep@gmail.com>
;; Maintainer: Johan Andersson <johan.rejeep@gmail.com>
;; ;; Package-Requires: ((s "1.6.0") (dash "2.0.0") (cl-lib "0.3") (f "0.6.1"))

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:



(require 'cl-lib)
(require 'f)
(require 's)
(require 'dash)



(cl-defstruct keg-commander-option
  "Structure describing an option.

Slots:

`flag' The option name (-f, -foo, --foo).

`description' Description of what the option does.

`function' Function to run when option used.

`default-values' Default values to call `function' with if none given.

`required' Required argument(s).

`optional' Optional argument(s).

`zero-or-more' Zero or more arguments allowed or required.

`one-or-more' One or more arguments allowed or required.

`to-string' String representation of option."
  flag flags description function default-values required optional
  zero-or-more one-or-more to-string)

(cl-defstruct keg-commander-command
  "Structure describing a command.

Slots:

`command' The command name (foo, foo-bar).

`description' Description of what the command does.

`function' Function to run when command used.

`default-values' Default values to call `function' with if none given.

`required' Required argument(s).

`optional' Optional argument(s).

`zero-or-more' Zero or more arguments allowed or required.

`one-or-more' One or more arguments allowed or required.

`to-string' String representation of command."
  command description function default-values required optional
  zero-or-more one-or-more to-string)

(cl-defstruct keg-commander-default-command
  "Structure describing the default command.

Slots:

`command' The name of the default command.

`arguments' The arguments to use for `command'."
  command arguments)

(cl-defstruct keg-commander-no-command
  "Structure describing the no command.

Slots:

`function' The function to call when no command.

`arguments' The arguments to use for `function'."
  function arguments)




(defvar keg-commander-options nil
  "List of all options.")

(defvar keg-commander-commands nil
  "List of all commands.")

(defvar keg-commander-parsing-done nil
  "Is parsing done or not.")

(defvar keg-commander-name nil
  "Name of program.")

(defvar keg-commander-description nil
  "Description of program.")

(defvar keg-commander-default-config nil
  "List of default CLI configuration options from config file.")

(defvar keg-commander-default-command nil
  "Command to use when no command parsed.")

(defvar keg-commander-no-command nil
  "Command to use when no command, only options and input.")

(defvar keg-commander-args nil
  "If parse directive is not called explicitly, use this first, then `command-line-args-left'.")

(defconst keg-commander-option-re
  "\\(-[A-Za-z0-9-]\\|--?[A-Za-z0-9][A-Za-z0-9-]+\\)"
  "Regex matching an option flag.")

(defconst keg-commander-command-re
  "\\([A-Za-z0-9][A-Za-z0-9-]*\\)"
  "Regex matching an command.")



(defun keg-commander--find-option (option)
  (-first
   (lambda (keg-commander-option)
     (equal (keg-commander-option-flag keg-commander-option) option))
   keg-commander-options))

(defun keg-commander--find-command (command)
  (-first
   (lambda (keg-commander-command)
     (equal (keg-commander-command-command keg-commander-command) command))
   keg-commander-commands))

(defun keg-commander--handle-options (arguments)
  (let (rest (i 0))
    (while (< i (length arguments))
      (let ((argument (nth i arguments)))
        (if (s-matches? (concat "\\`" keg-commander-option-re "\\'") argument)
            (let ((keg-commander-option (keg-commander--find-option argument)))
              (if keg-commander-option
                  (let* ((function (keg-commander-option-function keg-commander-option))
                         (default-values (keg-commander-option-default-values keg-commander-option))
                         (required (keg-commander-option-required keg-commander-option))
                         (optional (keg-commander-option-optional keg-commander-option))
                         (zero-or-more (keg-commander-option-zero-or-more keg-commander-option))
                         (one-or-more (keg-commander-option-one-or-more keg-commander-option))
                         (option-arguments
                          (when (or required optional)
                            (if (or (and required one-or-more) (and optional zero-or-more))
                                (let (next-arguments)
                                  (while (and (nth (1+ i) arguments) (not (s-matches? (s-concat "\\`" keg-commander-option-re "\\'") (nth (1+ i) arguments))))
                                    (setq i (1+ i))
                                    (push (nth i arguments) next-arguments))
                                  (nreverse next-arguments))
                              (when (and (nth (1+ i) arguments) (not (s-matches? (s-concat "\\`" keg-commander-option-re "\\'") (nth (1+ i) arguments))))
                                (setq i (1+ i))
                                (nth i arguments))))))
                    (cond (required
                           (if option-arguments
                               (if one-or-more
                                   (apply function option-arguments)
                                 (funcall function option-arguments))
                             (if one-or-more
                                 (error "Option `%s` requires at least one argument" argument)
                               (error "Option `%s` requires argument" argument))))
                          (optional
                           (if zero-or-more
                               (apply function (or option-arguments default-values))
                             (if option-arguments
                                 (funcall function option-arguments)
                               (apply function default-values))))
                          (t (funcall function))))
                (error "Option `%s` not available" argument)))
          (push argument rest)))
      (setq i (1+ i)))
    (nreverse rest)))

(defun keg-commander--handle-command (arguments)
  (let* ((command (car arguments))
         (rest (cdr arguments))
         (keg-commander-command (keg-commander--find-command command)))
    (if keg-commander-command
        (let ((function (keg-commander-command-function keg-commander-command))
              (default-values (keg-commander-command-default-values keg-commander-command))
              (required (keg-commander-command-required keg-commander-command))
              (optional (keg-commander-command-optional keg-commander-command))
              (zero-or-more (keg-commander-command-zero-or-more keg-commander-command))
              (one-or-more (keg-commander-command-one-or-more keg-commander-command)))
          (unless rest
            (setq rest default-values))
          (cond (required
                 (if rest
                     (apply function rest)
                   (if one-or-more
                       (error "Command `%s` requires at least one argument" command)
                     (error "Command `%s` requires argument" command))))
                (optional
                 (apply function rest))
                (t
                 (funcall function))))
      (if keg-commander-no-command
          (let ((function (keg-commander-no-command-function keg-commander-no-command)))
            (unless arguments
              (setq arguments (keg-commander-no-command-arguments keg-commander-no-command)))
            (apply function arguments))
        (when command (error "Command `%s` not available" command))))))

(defun keg-commander--usage-commands ()
  (nreverse keg-commander-commands))

(defun keg-commander--usage-options ()
  (let ((-compare-fn
         (lambda (option-a option-b)
           (string=
            (keg-commander-option-to-string option-a)
            (keg-commander-option-to-string option-b)))))
    (nreverse (-uniq keg-commander-options))))


;;;; Usage

(defun keg-commander--usage-padding ()
  (let (max-option (max-option-value 0) max-command (max-command-value 0))
    (--each keg-commander-options
      (setq max-option-value (max max-option-value (length (keg-commander-option-to-string it)))))
    (--each keg-commander-commands
      (setq max-command-value (max max-command-value (length (keg-commander-command-to-string it)))))
    (+ (max max-option-value max-command-value) 10)))

(defun keg-commander--usage-command-or-option (to-string description)
  (unless (listp description)
    (setq description (list description)))
  (let ((padding (keg-commander--usage-padding)))
    (s-concat
     " "
     to-string
     (s-repeat (- padding (length to-string)) " ")
     (car description)
     (s-join
      ""
      (--map
       (s-concat "\n" (s-repeat (1+ padding) " ") it)
       (cdr description))))))

(defun keg-commander--usage-command (keg-commander-command)
  (let ((to-string (keg-commander-command-to-string keg-commander-command))
        (description (keg-commander-command-description keg-commander-command)))
    (keg-commander--usage-command-or-option to-string description)))

(defun keg-commander--usage-option (keg-commander-option)
  (let ((to-string (keg-commander-option-to-string keg-commander-option))
        (description (keg-commander-option-description keg-commander-option)))
    (keg-commander--usage-command-or-option to-string description)))

(defun keg-commander-usage ()
  "Return usage information as a string."
  (let ((name (or keg-commander-name (f-filename load-file-name)))
        (commands-string
         (s-join "\n" (--map (keg-commander--usage-command it) (keg-commander--usage-commands))))
        (options-string
         (s-join "\n" (--map (keg-commander--usage-option it) (keg-commander--usage-options)))))
    (s-concat
     (format "USAGE: %s [COMMAND] [OPTIONS]" name)
     (when keg-commander-description
       (s-concat "\n\n" keg-commander-description))
     (when keg-commander-commands
       (s-concat "\n\nCOMMANDS:\n\n" commands-string))
     (when keg-commander-options
       (s-concat "\n\nOPTIONS:\n\n" options-string)))))

(defun keg-commander-usage-for (command-name)
  "Return description for COMMAND-NAME.

Return value is always a list with one item for each row."
  (-if-let (command (keg-commander--find-command command-name))
      (let ((description (keg-commander-command-description command)))
        (unless (listp description)
          (setq description (list description)))
        description)
    (error "No such command: %s" command-name)))

(defun keg-commander-print-usage ()
  "Print usage information."
  (princ (concat (keg-commander-usage) "\n")))

(defun keg-commander-print-usage-for (command-name)
  "Print usage information for COMMAND-NAME."
  (-each (keg-commander-usage-for command-name)
         (lambda (row)
           (princ (concat row "\n")))))

(defun keg-commander-print-usage-and-exit (&optional exit-code)
  "Print usage information and exit.

If EXIT-CODE is specified, with with this code.  Default exit
code is 0."
  (keg-commander-print-usage)
  (kill-emacs (or exit-code 0)))

(defun keg-commander-print-usage-for-and-exit (command-name &optional exit-code)
  "Print usage information for COMMAND-NAME and exit.

If EXIT-CODE is specified, with with this code.  Default exit
code is 0."
  (keg-commander-print-usage-for command-name)
  (kill-emacs (or exit-code 0)))



(defun keg-commander-option (flags description function &rest default-values)
  (let (required optional zero-or-more one-or-more)
    (-map
     (lambda (flag)
       (let ((to-string flags))
         (let ((matches (s-match (concat "\\`" keg-commander-option-re " " "<\\(.+\\)>" "\\'") flag)))
           (when matches
             (setq flag (nth 1 matches))
             (when (nth 2 matches)
               (setq required t)
               (if (equal (nth 2 matches) "*")
                   (setq one-or-more t)))))
         (let ((matches (s-match (concat "\\`" keg-commander-option-re " " "\\[\\(.+\\)\\]" "\\'") flag)))
           (when matches
             (setq flag (nth 1 matches))
             (when (nth 2 matches)
               (setq optional t)
               (if (equal (nth 2 matches) "*")
                   (setq zero-or-more t)))))
         (add-to-list
          'keg-commander-options
          (make-keg-commander-option
           :flag flag
           :flags flags
           :description description
           :function function
           :default-values default-values
           :required required
           :optional optional
           :zero-or-more zero-or-more
           :one-or-more one-or-more
           :to-string to-string))))
     (-map 's-trim (s-split "," flags)))))

(defun keg-commander-command (command description function &rest args)
  (let* (required
         optional
         zero-or-more
         one-or-more
         (to-string command)
         (default-values (-take-while 'stringp args)))
    (let ((matches (s-match (concat "\\`" keg-commander-command-re " " "<\\(.+\\)>" "\\'") command)))
      (when matches
        (setq command (nth 1 matches))
        (when (nth 2 matches)
          (setq required t)
          (if (equal (nth 2 matches) "*")
              (setq one-or-more t)))))
    (let ((matches (s-match (concat "\\`" keg-commander-command-re " " "\\[\\(.+\\)\\]" "\\'") command)))
      (when matches
        (setq command (nth 1 matches))
        (when (nth 2 matches)
          (setq optional t)
          (if (equal (nth 2 matches) "*")
              (setq zero-or-more t)))))
    (add-to-list
     'keg-commander-commands
     (make-keg-commander-command
      :command command
      :description description
      :function function
      :default-values default-values
      :required required
      :optional optional
      :zero-or-more zero-or-more
      :one-or-more one-or-more
      :to-string to-string))))

(defun keg-commander-ignore-p ()
  "Returns true if parsing should be ignored, false otherwise.

By setting the variable `keg-commander-ignore' to true, the parsing
will be ignored.  This is useful in for example unit tests."
  (and (boundp 'keg-commander-ignore) keg-commander-ignore))

(defun keg-commander-parse (arguments)
  (unless (keg-commander-ignore-p)
    (let* ((rest-config (keg-commander--handle-options keg-commander-default-config))
           (rest (or (keg-commander--handle-options arguments) rest-config)))
      (unless rest
        (if keg-commander-default-command
            (let ((command (keg-commander-default-command-command keg-commander-default-command))
                  (arguments (keg-commander-default-command-arguments keg-commander-default-command)))
              (setq rest (cons command arguments)))))
      (keg-commander--handle-command rest))))

(defun keg-commander-name (name)
  (setq keg-commander-name name))

(defun keg-commander-description (description)
  (setq keg-commander-description description))

(defun keg-commander-config (file)
  (when (f-file? file)
    (let ((lines (-reject 's-blank? (s-lines (f-read-text file 'utf-8)))))
      (setq keg-commander-default-config
            (-flatten (--map (s-split " " it) lines))))))

(defun keg-commander-default (command-or-function arguments)
  (if (stringp command-or-function)
      (setq
       keg-commander-default-command
       (make-keg-commander-default-command
        :command command-or-function
        :arguments arguments))
    (setq
     keg-commander-no-command
     (make-keg-commander-no-command
      :function command-or-function
      :arguments arguments))))



(defun keg-commander--make-args (args)
  "Make proper command/option arguments from ARGS.

ARGS is the args that are passed to the `command' and `option'
directives. The return value is a list complete list that can be
sent to `keg-commander-command' and `keg-commander-options'.

If ARGS does not contain documentation, it is fetched from the
function doc string."
  (when (functionp (nth 1 args))
    (let ((description
           (-if-let (description (documentation (nth 1 args)))
               (s-lines description)
             "")))
      (setq args (-insert-at 1 description args))))
  args)

(defmacro keg-commander (&rest forms)
  `(progn
     (setq keg-commander-default-config nil)
     (setq keg-commander-options nil)
     (setq keg-commander-commands nil)
     (setq keg-commander-name nil)
     (setq keg-commander-description nil)
     (setq keg-commander-default-command nil)
     (setq keg-commander-no-command nil)
     (setq keg-commander-parsing-done nil)
     (-each
      ',forms
      (lambda (form)
        (cl-case (car form)
          (option
           (cl-destructuring-bind (_ &rest args) form
             (apply 'keg-commander-option (keg-commander--make-args args))))
          (command
           (cl-destructuring-bind (_ &rest args) form
             (apply 'keg-commander-command (keg-commander--make-args args))))
          (parse
           (cl-destructuring-bind (_ arguments) form
             (keg-commander-parse arguments)
             (setq keg-commander-parsing-done t)))
          (name
           (cl-destructuring-bind (_ name) form
             (keg-commander-name name)))
          (description
           (cl-destructuring-bind (_ description) form
             (keg-commander-description description)))
          (config
           (cl-destructuring-bind (_ file) form
             (keg-commander-config file)))
          (default
            (cl-destructuring-bind (_ command-or-function &rest arguments) form
              (keg-commander-default command-or-function arguments)))
          (t (error "Unknown directive: %S" form)))))
     (unless keg-commander-parsing-done
       (keg-commander-parse (or keg-commander-args (cdr command-line-args-left))))))

(provide 'keg-commander)

;;; keg-commander.el ends here
