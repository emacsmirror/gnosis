;;; gnosis-algorithm.el --- Spaced Repetition Algorithm for Gnosis  -*- lexical-binding: t; -*-

;; Copyright (C) 2023  Thanos Apollo

;; Author: Thanos Apollo <public@thanosapollo.org>
;; Keywords: extensions
;; URL: https://git.thanosapollo.org/gnosis
;; Version: 0.0.1

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

;; Handles date calculation as well as ef & interval calculations.

;; This file contains the algorithm for the spaced repetition system used in Gnosis.
;; Gnosis algorithm is inspired by the SM-2 algorithm used in Anki, but has been
;; modified to fit the needs of Gnosis.

;;; Code:

(require 'cl-lib)
(require 'calendar)

(defcustom gnosis-algorithm-interval '(1 3)
  "Gnosis initial interval for successful reviews.

First item: First interval,
Second item: Second interval."
  :group 'gnosis
  :type '(list integer))

(defcustom gnosis-algorithm-ef '(0.35 0.30 1.3)
  "Gnosis easiness factor.

First item : Increase factor
Second item: Decrease factor
Third item : Starting total ef

Note: Starting total ef should not be above 3.0"
  :group 'gnosis
  :type '(list float))

(defcustom gnosis-algorithm-ff 0.5
  "Gnosis forgetting factor.

Used to calcuate new interval for failed questions.

NOTE: Do not change this value above 1"
  :group 'gnosis
  :type 'float)

(defcustom gnosis-algorithm-ef-increase 0.1
  "Increase ef increase value by this amount for every
`gnosis-algorithm-ef-threshold' number of successful reviews."
  :group 'gnosis
  :type 'float)

(defcustom gnosis-algorithm-ef-decrease 0.2
  "Decrease ef decrease value by this amount for every
`gnosis-algorithm-ef-threshold' number of failed reviews."
  :group 'gnosis
  :type 'float)

(defcustom gnosis-algorithm-ef-threshold 3
  "Threshold for updating ef increase/decrease values.

Refers to the number of consecutive successful or failed reviews."
  :group 'gnosis
  :type 'integer)

(defun gnosis-algorithm-replace-at-index (index new-item list)
  "Replace item at INDEX with NEW-ITEM in LIST."
  (cl-loop for item in list
	   for i from 0
	   collect (if (= i index) new-item item)))

(defun gnosis-algorithm-round-items (list)
  "Round all items in LIST to 2 decimal places."
  (cl-loop for item in list
	   collect (/ (round (* item 100)) 100.0)))

(defun gnosis-algorithm-date (&optional offset)
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

(defun gnosis-algorithm-date-diff (date)
  "Find the difference between the current date and the given DATE.

DATE format must be given as (year month day)."
  (let ((given-date (encode-time 0 0 0 (caddr date) (cadr date) (car date))))
    (- (time-to-days (current-time))
       (time-to-days given-date))))

(cl-defun gnosis-algorithm-next-ef (&key ef success increase decrease threshold
					 c-successes c-failures)
  "Returns the new EF, (increase-value decrease-value total-value)

Calculate the new e-factor given existing EF and SUCCESS, either t or nil.

Next EF is calculated as follows:

Upon a successful review, increase total ef value (nth 2) by
ef-increase value (nth 0).

Upon a failed review, decrease total ef by ef-decrease value (nth 1).

For every THRESHOLD of C-SUCCESSES (consecutive successful reviews)
reviews, increase ef-increase by INCREASE.

For every THRESHOLD of C-FAILURES reviews, decrease ef-decrease value
by DECREASE."
  (cl-assert (listp ef) nil "Assertion failed: ef must be a list")
  (cl-assert (booleanp success) nil "Assertion failed: success must be a boolean value")
  (cl-assert (numberp increase) nil "Assertion failed: increase must be a number")
  (cl-assert (numberp decrease) nil "Assertion failed: decrease must be a number")
  (cl-assert (numberp threshold) nil "Assertion failed: threshold must be a number")
  (let ((threshold-p (= (% (max 1 (if success c-successes c-failures)) threshold) 0))
	(new-ef (if success (gnosis-algorithm-replace-at-index 2 (+ (nth 2 ef) (nth 0 ef)) ef)
		  (gnosis-algorithm-replace-at-index 2 (max 1.3 (- (nth 2 ef) (nth 1 ef))) ef))))
    (cond ((and success threshold-p)
	   (setf new-ef (gnosis-algorithm-replace-at-index 0 (+ (nth 0 ef) increase) new-ef)))
	  ((and (not success) threshold-p
		(setf new-ef (gnosis-algorithm-replace-at-index 1 (+ (nth 1 ef) decrease) new-ef)))))
    (gnosis-algorithm-round-items new-ef)))

(cl-defun gnosis-algorithm-next-interval (&key last-interval ef success successful-reviews
					       failure-factor initial-interval)
  "Calculate next interval."
  (cl-assert (< gnosis-algorithm-ff 1) "Value of `gnosis-algorithm-ff' must be lower than 1")
  ;; This should only occur in testing env or when the user has made breaking changes.
  (cl-assert (> (nth 2 ef) 1) "Total ef value must be above 1")
  (let* ((ef (nth 2 gnosis-algorithm-ef))
	 (interval (cond ((and (= successful-reviews 0) success)
			  (car initial-interval))
			 ((and (= successful-reviews 1) success)
			  (cadr initial-interval))
			 (t (if success
				(* ef last-interval)
			      (* failure-factor last-interval))))))
    (gnosis-algorithm-date (round interval))))


(provide 'gnosis-algorithm)
;;; gnosis-algorithm.el ends here
