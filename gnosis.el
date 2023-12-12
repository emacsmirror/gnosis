;;; gnosis.el --- Learning tool for GNU Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2023  Thanos Apollo

;; Author: Thanos Apollo <public@thanosapollo.org>
;; Keywords: extensions
;; URL: https://git.thanosapollo.org/gnosis
;; Version: 0.0.1

;; Package-Requires: ((emacs "27.2") (compat "29.1.4.2"))

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

;; Work in progress

;;; Code:

;; TODO: Create cloze question type & make it easily extensible for
;; other types


(require 'emacsql)
(require 'cl-lib)
(require 'animate)

(defgroup gnosis nil
  "Spaced repetition learning tool."
  :group 'external
  :prefix "gnosis-")

(defvar gnosis-db (emacsql-sqlite (concat user-emacs-directory "gnosis.db")))

(cl-defun gnosis--select (table values &optional (restrictions '1=1))
  "Select VALUES from TABLE, optionally with RESTRICTIONS."
  (emacsql gnosis-db `[:select ,values :from ,table :where ,restrictions]))

(cl-defun gnosis--create-table (table-name &optional values)
  "Create TABLE-NAME for VALUES."
  (emacsql gnosis-db `[:create-table ,table-name ,values]))

(cl-defun gnosis--drop-table (table)
  "Drop TABLE from gnosis-db."
  (emacsql gnosis-db `[:drop-table ,table]))

(cl-defun gnosis--insert-into (table-name values)
  "Insert VALUES to TABLE-NAME."
  (emacsql gnosis-db `[:insert :into ,table-name :values ,values]))

(defun gnosis--get (table value id)
  "Get VALUE for question ID from TABLE."
  (caar (gnosis--select table value `(= id ,id))))

(defun gnosis--display-question (id)
  "Display main row for question ID."
  (let ((question (gnosis--get 'notes 'main id)))
    ;; Animate.el is used only for testing purposes.
    (animate-string question 5)))

(defun gnosis--ask-input (prompt)
  "PROMPT user for input until `q' is given.

The user is prompted to provide input for the 'PROMPT' message, and
the returns the list of inputs in reverse order."
  (let ((input nil))
    (while (not (equal (car input) "q"))
      (add-to-list 'input (read-string (concat prompt " (q for quit): "))))
    (when (equal (car input) "q")
      (pop input))
    (reverse input)))

(cl-defun gnosis-create-mcq-question (&key question choices correct-answer tags)
  "Create a QUESTION with a list of multiple CHOICES.

MCQ type questions consist of a main `QUESTION', which is displayed &
the user will be prompted to find the `CORRECT-ANSWER', which is the
correct number choice of `CHOICES'.

TAGS are used to organize questions.

This function can be used interactively, or if you prefer you may also
use it like this:
 (gnosis-create-mcq-question
  :question \"Which one is the greatest editor?\"
  :choices (list \"Emacs\" \"Vim\" \"VSCode\" \"Ed\")
  :correct-answer 1
  :tags (list \"emacs\" \"editors\"))"
  (interactive
   (list :question (read-string "Question: ")
         :choices (gnosis--ask-input "Choices")
         :correct-answer (string-to-number (read-string "Which is the correct answer (number)? "))
	 :tags (gnosis--ask-input "Tags")))
  (gnosis--insert-into 'notes `([nil "mcq" ,question ,choices ,correct-answer 0 0 ,tags])))

(defun gnosis-create-question (type)
  "Create question as TYPE."
  (interactive (list (completing-read "Type: " '(MCQ Cloze Basic))))
  (pcase type
    ("MCQ" (call-interactively 'gnosis-create-mcq-question))
    ("Cloze" (message "Not ready yet."))
    ("Basic" (message "Not ready yet."))
    (_ (message "No such type."))))

(defun gnosis-mcq-answer (id)
  "Choose the correct answer, from mcq choices for question ID."
  (let ((choices (gnosis--get 'notes 'options id))
	(history-add-new-input nil)) ;; Disable history
    (completing-read "Answer: " choices)))

(defun gnosis-review-mcq-choices (id)
  "Display multiple choice answers for question ID."
  (let ((canswer (gnosis--get 'notes 'answer id))
	(choices (gnosis--get 'notes 'options id))
	(user-choice (gnosis-mcq-answer id)))
    (if (equal (nth (- canswer 1) choices) user-choice)
	(message "Correct!")
      (message "False"))))

(defun gnosis-review (id)
  "Start review for question ID."
  (let ((type (gnosis--get 'notes 'type id)))
    (pcase type
      ("mcq" (gnosis-review-mcq-choices id))
      ("basic" (message "Not Ready yet."))
      ("cloze" (message "Not Ready yet.")))))

;; testing
(defun gnosis-test-buffer ()
  "Create testing buffer."
  (interactive)
  (with-current-buffer
      (switch-to-buffer (get-buffer-create "*gnosis*"))
    (read-only-mode 0)
    (erase-buffer)
    (gnosis--display-question 1)
    (gnosis-review 1)
    (gnosis-mode)))

(defun gnosis-init ()
  "Create notes content table."
  (interactive)
  (condition-case nil
      (gnosis--drop-table 'notes)
    (error (message "No NOTES table to drop, recreating new one.")))
  (gnosis--create-table 'notes '([(id integer :primary-key)
				  (type text)
				  (main text)
				  options
				  answer
				  tags
				  rev_log
				  rev_score])))

;; Gnosis mode
(define-derived-mode gnosis-mode special-mode "Gnosis"
  "Gnosis Mode."
  :interactive t
  (display-line-numbers-mode 0)
  :lighter " gnosis-mode")

;;; gnosis.el ends here