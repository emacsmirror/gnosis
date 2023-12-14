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

(defcustom gnosis-interval '(1 3)
  "Gnosis initial interval.

Interval by which a new question is displayed or when it's ef is at 1.3.

First item: First interval
Second item: Second interval."
  :group 'gnosis
  :type 'list)

(defcustom gnosis-ef '(0.3 0.3)
  "Gnosis easiness factor.

First item : Increase factor
Second item: Decrease factor"
  :group 'gnosis
  :type 'list)

(defcustom gnosis-ff 0.5
  "Gnosis forgetting factor.

Used to calcuate new interval for failed questions."
  :group 'gnosis
  :type 'float)

(defvar gnosis-db (emacsql-sqlite (concat user-emacs-directory "gnosis.db")))

(cl-defun gnosis--select (value table &optional (restrictions '1=1))
  "Select VALUE from TABLE, optionally with RESTRICTIONS."
  (emacsql gnosis-db `[:select ,value :from ,table :where ,restrictions]))

(cl-defun gnosis--create-table (table &optional values)
  "Create TABLE for VALUES."
  (emacsql gnosis-db `[:create-table ,table ,values]))

(cl-defun gnosis--drop-table (table)
  "Drop TABLE from gnosis-db."
  (emacsql gnosis-db `[:drop-table ,table]))

(cl-defun gnosis--insert-into (table values)
  "Insert VALUES to TABLE."
  (emacsql gnosis-db `[:insert :into ,table :values ,values]))

(cl-defun gnosis-update (table value where)
  "Update records in TABLE with to new VALUE based on the given WHERE condition.
Example:
 (gnosis-update 'notes '(= main \"NEW VALUE\") '(= id 12))"
  (emacsql gnosis-db `[:update ,table :set ,value :where ,where]))

(defun gnosis-get (value table &optional restrictions)
  "Get VALUE from TABLE, optionally with where RESTRICTIONS."
  (caar (gnosis--select value table restrictions)))

(defun gnosis--delete (table value)
  "From TABLE use where to delete VALUE."
  (emacsql gnosis-db `[:delete :from ,table :where ,value]))

(defun gnosis--display-question (id)
  "Display main row for question ID."
  (let ((question (gnosis-get 'main 'notes `(= id ,id))))
    (erase-buffer)
    (insert question 1)
    (sit-for 0.5)))

(defun gnosis--ask-input (prompt)
  "PROMPT user for input until `q' is given.
  
  The user is prompted to provide input for the 'PROMPT' message, and
  the returns the list of inputs in reverse order."
  (let ((input-list nil)
        (input ""))
    (while (not (string= input "q"))
      (setq input (read-string (concat prompt " (q for quit): ")))
      (push input input-list))
    (when (string= (car input-list) "q")
      (pop input-list))
    (nreverse input-list)))

(defun gnosis-add-deck (name)
  "Create deck with NAME."
  (interactive (list (read-string "Deck Name: ")))
  (gnosis--insert-into 'decks `([nil ,name])))

(defun gnosis--get-deck-name ()
  "Get name from table DECKS."
  (when (equal (gnosis--select 'name 'decks) nil)
    (error "No decks found"))
  (completing-read "Deck: " (gnosis--select 'name 'decks)))

(defun gnosis--get-deck-id ()
  "Select id for deck name."
  (let ((deck (gnosis--get-deck-name)))
    (gnosis-get 'id 'decks `(= name ,deck))))

(defun gnosis-delete-deck (id)
  "Delete deck with id value of ID."
  (interactive (list (gnosis--get-deck-id)))
  (gnosis--delete 'decks `(= id ,id)))

(cl-defun gnosis-add-note-mcq (&key deck question choices correct-answer tags)
  "Create a NOTE with a list of multiple CHOICES.

MCQ type consists of a main `QUESTION' that is displayed to the user.
The user will be prompted to select the correct answer from a list of
`CHOICES'. The `CORRECT-ANSWER' should be the index of the correct
choice in the `CHOICES' list. Each note must correspond to one `DECK'.
TAGS are used to organize questions."
  (interactive
   (list :deck (gnosis--get-deck-id)
	 :question (read-string "Question: ")
         :choices (gnosis--ask-input "Choices")
         :correct-answer (string-to-number (read-string "Which is the correct answer (number)? "))
	 :tags (when (equal (gnosis--ask-input "Tags") nil) 'untagged)))
  (when (equal (numberp correct-answer) nil)
    (error "The correct answer must be the number of the correct answer"))
  (gnosis--insert-into 'notes `([nil "mcq" ,question ,choices ,correct-answer ,tags ,deck]))
  ;; Get last inserted note-id
  (let ((note-id (caar (last (gnosis--select 'id 'notes)))))
    (gnosis--insert-into 'review `([,note-id ,gnosis-ef ,gnosis-ff 0 0 0]))))

(defun gnosis-add-note (type)
  "Create note as TYPE."
  (interactive (list (completing-read "Type: " '(MCQ Cloze Basic))))
  (pcase type
    ("MCQ" (call-interactively 'gnosis-add-note-mcq))
    ("Cloze" (message "Not ready yet."))
    ("Basic" (message "Not ready yet."))
    (_ (message "No such type."))))

(defun gnosis-mcq-answer (id)
  "Choose the correct answer, from mcq choices for question ID."
  (let ((choices (gnosis-get 'options 'notes `(= id ,id)))
	(history-add-new-input nil)) ;; Disable history
    (completing-read "Answer: " choices)))

(defun gnosis-review-mcq-choices (id)
  "Display multiple choice answers for question ID."
  (let ((answer (gnosis-get 'answer 'notes `(= id ,id)))
	(choices (gnosis-get 'options 'notes `(= id ,id)))
	(user-choice (gnosis-mcq-answer id)))
    (if (equal (nth (- answer 1) choices) user-choice)
	(message "Correct!")
      (message "False"))))

(defun gnosis-review (id)
  "Start review for question ID."
  (let ((type (gnosis-get 'type 'notes `(= id id))))
    (pcase type
      ("mcq" (gnosis-review-mcq-choices id))
      ("basic" (message "Not Ready yet."))
      ("cloze" (message "Not Ready yet."))
      (_ (error "Malformed note type")))))

;; Database Schemas
(defvar gnosis-db-decks-schema '([(id integer :primary-key :autoincrement)
				  (name text :not-null)]))

(defvar gnosis-db-notes-schema '([(id integer :primary-key :autoincrement)
				  (type text :not-null)
				  (main text :not-null)
				  (options text :not-null)
				  (answer text :not-null)
				  (tags text :default untagged)
				  (deck-id integer)]
				 (:foreign-key [deck-id] :references decks [id]
					       :on-delete :cascade)))

(defvar gnosis-db-review-schema '([(id integer :not-null) ;; note-id
				   (ef integer :not-null) ;; Easiness factor
				   (ff integer :not-null) ;; Forgetting factor
				   (n integer :not-null) ;; Number of reviews
				   (interval integer :not-null)] ;; Interval
				  (:foreign-key [id] :references notes [id]
						:on-delete :cascade)))

(defvar gnosis-db-review-log-schema '([(id integer :not-null) ;; note-id
				       (last-rev integer :not-null) ;; Last review date
				       (next-rev integer :not-null) ;; Next review date
				       (failures integer :not-null)] ;; Number of consecutive review failures
				      (:foreign-key [id] :references notes [id]
						    :on-delete :cascade)))


;; testing
(defun gnosis-test-buffer ()
  "Create testing buffer."
  (interactive)
  (with-current-buffer
      (switch-to-buffer (get-buffer-create "*gnosis*"))
    (read-only-mode 0)
    (erase-buffer)
    (gnosis--display-question 4)
    (gnosis-review 4)
    (gnosis-mode)))

(defun gnosis-init ()
  "Create notes content table."
  (interactive)
  ;;(make-directory (concat user-emacs-directory "gnosis"))
  (condition-case nil
      (gnosis--drop-table 'notes)
    (error (message "No NOTES table to drop.")))
  (condition-case nil
      (gnosis--drop-table 'decks)
    (error (message "No DECKS table to drop.")))
  (condition-case nil
      (gnosis--drop-table 'review)
    (error (message "No REVIEW table to drop.")))
  ;; Enable foreign_keys
  (emacsql gnosis-db "PRAGMA foreign_keys = ON")
  ;; Create decks table
  (gnosis--create-table 'decks gnosis-db-decks-schema)
  ;; Create notes table
  (gnosis--create-table 'notes gnosis-db-notes-schema)
  ;; Create review table
  (gnosis--create-table 'review gnosis-db-review-schema)
  ;; Create review-log table
  (gnosis--create-table 'review-log gnosis-db-review-log-schema)
  (gnosis-add-deck "Anatomy"))

;; Gnosis mode ;;
;;;;;;;;;;;;;;;;;

(define-derived-mode gnosis-mode special-mode "Gnosis"
  "Gnosis Mode."
  :interactive t
  (display-line-numbers-mode 0)
  :lighter " gnosis-mode")

;; Gnosis Algorithm ;;
;;;;;;;;;;;;;;;;;;;;;;

(defun gnosis-current-date (&optional offset)
  "Return the current date in a list (year month day).
Optional integer OFFSET is a number of days from the current date."
  (let* ((now (decode-time))
         (now (list (decoded-time-month now)
                    (decoded-time-day now)
                    (decoded-time-year now))))
    (let ((date (if (zerop (or offset 0))
                    now
                  (calendar-gregorian-from-absolute
                   (+ offset (calendar-absolute-from-gregorian now))))))
      (list (nth 2 date) (nth 0 date) (nth 1 date)))))

(defun gnosis-date-difference (year month day)
  "Find the difference between the current date and the given date.

The structure of the given date is (YEAR MONTH DAY)."
  (let ((current-date (gnosis-date-current))
	(given-date (encode-time 0 0 0 day month year)))
    (- (time-to-days (current-time))
       (time-to-days given-date))))

(defun gnosis-calculate-e-factor (ef quality)
  "Calculate new e-factor given existing EF and binary QUALITY, 0 or 1."
  (cond
   ((not (numberp quality))
    (error "Invalid argument passed to gnosis-calculate-e-factor"))
   ((= quality 0) ;; If the quality score is 0 (fail), decrease the ef by a small penalty
    (max 1.3 (- ef (cadr gnosis-ef))))
   ((= quality 1) ;; If the quality score is 1 (pass), increase the ef by a small reward
    (+ ef (car gnosis-ef)))
   (t (error "Invalid quality score passed to gnosis-calculate-e-factor"))))

(defun gnosis-calculate-next-interval (last-interval n ef success ff)
  "Calculate next interval.
- LAST-INTERVAL : The number of days since the item was last reviewed.
- N : Number of times the item has been reviewed.
- EF : The 'easiness factor'.
- SUCCESS : Success of the recall, ranges from 0 (unsuccessful) to 1
  (successful).
- FF: Failure factor

Returns a tuple: (INTERVAL N EF) where,
- INTERVAL : The number of days until the item should next be reviewed.
- N : Incremented by 1.
- EF : Modified based on the recall success for the item."
  (cl-assert (and (>= success 0)
		  (<= success 1)))
  ;; Calculate the next easiness factor.
  (let* ((next-ef (gnosis-calculate-e-factor ef success))
         ;; Calculate the next interval.
         (interval
          (cond
	   ;; Show item same day on the first review
	   ((= n 0) 0)
           ;; Immediately next day if it's the first time review.
           ((<= n 1) (car gnosis-interval))
           ;; After 3 days if it's second review.
           ((= n 2) (cadr gnosis-interval))
           ;; Increase last interval by 1 if recall was successful. Keep last interval if unsuccessful.
           (t (if (= success 1)
                  (* ef last-interval)
                (* ff last-interval))))))
    (list (round interval) (1+ n) next-ef)))


(provide 'gnosis)
;;; gnosis.el ends here
