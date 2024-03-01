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

;; Work in progress

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
`gnosis-algorithm-ef-frequency' number of successful reviews."
  :group 'gnosis
  :type 'float)

(defcustom gnosis-algorithm-ef-decrease 0.1
  "Decrease ef decrease value by this amount for every
`gnosis-algorithm-ef-frequency' number of failed reviews."
  :group 'gnosis
  :type 'float)

(defcustom gnosis-algorithm-ef-frequency 3
  "Frequency for updating ef increase and decrease values."
  :group 'gnosis
  :type 'integer)

(defun gnosis-algorithm-replace-at-index (index new-item list)
  "Replace item at INDEX with NEW-ITEM in LIST."
  (cl-loop for item in list
	   for i from 0
	   collect (if (= i index) new-item item)))


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

DATE format must be given as (yyyy mm dd)
The structure of the given date is (YEAR MONTH DAY)."
  (let ((given-date (encode-time 0 0 0 (caddr date) (cadr date) (car date))))
    (- (time-to-days (current-time))
       (time-to-days given-date))))


(defun gnosis-algorithm-e-factor (ef success)
  "Calculate the new e-factor given existing EF and SUCCESS, either t or nil."
  (pcase success
    (`t (+ ef (car gnosis-algorithm-ef)))
    (`nil (max 1.3 (- ef (cadr gnosis-algorithm-ef))))))


(cl-defun gnosis-algorithm-next-interval (&key last-interval review-num ef success failure-factor successful-reviews successful-reviews-c fails-c fails-t initial-interval)
  "Calculate next interval.
- LAST-INTERVAL : The number of days since the item was last reviewed.
-review-num: Number of times the item has been reviewed.
- EF : Easiness Factor.
- SUCCESS : Success of the recall, ranges from 0 (unsuccessful) to 1
  (successful).
- FF: Failure factor
- SUCCESSFUL-REVIEWS : Number of successful reviews.
- SUCCESSFULL-REVIEWS-C: Successful reviews in a row.
- FAILS-C: Failed reviews in a row.
- FAILS-T: Total failed reviews.
- INITIAL-INTERVAL: Initial intervals for successful reviews.

Returns a list of: (INTERVAL N EF) where,
- Next review date in (yyyy mm dd) format.
- REVIEW-NUM: Incremented by 1.
- EF : Modified based on the recall success for the item."
  ;; Check if gnosis-algorithm-ff is lower than 1 & is total-ef above 1.3
  (cond ((>= gnosis-algorithm-ff 1)
	 (error "Value of `gnosis-algorithm-ff' must be lower than 1"))
	((< (nth 2 gnosis-algorithm-ef) 1.3)
	 (error "Value of total-ef from `gnosis-algorithm-ef' must be above 1.3")))
  ;; Calculate the next easiness factor.
  (let* ((next-ef (gnosis-algorithm-e-factor ef success))
         (interval
          (cond
	   ;; TODO: Rewrite this!
           ;; First successful review -> first interval
           ((and (= successful-reviews 0) success
		 (car initial-interval)))
           ;; Second successful review -> second interval
           ((and (= successful-reviews 1) success)
	    (cadr initial-interval))
	   ;; When successful-reviews-c is above 3, use 150% or 180%
	   ;; of ef depending on the value of successful-reviews
	   ((and success
		 (>= successful-reviews-c 3)
		 (>= review-num 5)
		 (> last-interval 1))
	    (* (* ef (if (>= successful-reviews 10) 1.8 1.5)) last-interval))
	   ((and (equal success nil)
		 (> fails-c 3)
		 (>= review-num 5)
		 (> last-interval 1))
	    ;; When fails-c is above 3, use 150% or 180% of
	    ;; failure-factor depending on the value of total failed
	    ;; reviews.
	    (* (max (min 0.8 (* failure-factor (if (>= fails-t 10) 1.8 1.5)))
		     failure-factor)
		last-interval))
	   ;; For everything else
           (t (if success
                  (* ef last-interval)
                (* failure-factor last-interval))))))
    (list (gnosis-algorithm-date (round interval)) next-ef)))

(provide 'gnosis-algorithm)
;;; gnosis-algorithm.el ends here
