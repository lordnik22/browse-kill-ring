;;; browse-mark-ring.el --- interactively jump to items from mark-ring -*- coding: utf-8 -*-

;; Copyright (C) 2001, 2002 Colin Walters <walters@verbum.org>

;; Author: lordnik22, Colin Walters <walters@verbum.org>
;; Maintainer: browse-mark-ring <browse-mark-ring@tonotdo.com>
;; Created: 7 Apr 2001
;; Version: 2.0.0
;; URL: https://github.com/lordnik22/browse-mark-ring
;; Keywords: convenience

;; This file is not currently part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program ; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;;; Code:
(eval-when-compile
  (require 'cl-lib))
(require 'delsel)
(require 'simple)

(defgroup browse-mark-ring nil
  "A package for browsing and inserting the items in `kill-ring'."
  :link '(url-link "https://github.com/browse-mark-ring/browse-mark-ring")
  :group 'convenience)

(defvar browse-mark-ring-display-styles
  '((separated . browse-mark-ring-insert-as-separated)
    (one-line . browse-mark-ring-insert-as-one-line)))

(defcustom browse-mark-ring-display-style 'separated
  "How to display the kill ring items.

If `one-line', then replace newlines with \"\\n\" for display.

If `separated', then display `browse-mark-ring-separator' between
entries."
  :type '(choice (const :tag "One line" one-line)
		 (const :tag "Separated" separated))
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-quit-action 'save-and-restore
  "What action to take when `browse-mark-ring-quit' is called.

If `bury-buffer', then simply bury the *Kill Ring* buffer, but keep
the window.

If `bury-and-delete-window', then bury the buffer, and (if there is
more than one window) delete the window.

If `save-and-restore', then save the window configuration when
`browse-mark-ring' is called, and restore it at quit.  This is
the default.

If `kill-and-delete-window', then kill the *Kill Ring* buffer, and
delete the window on close.

Otherwise, it should be a function to call."
  :type '(choice (const :tag "Bury buffer" :value bury-buffer)
		 (const :tag "Delete window" :value delete-window)
		 (const :tag "Save and restore" :value save-and-restore)
		 (const :tag "Bury buffer and delete window" :value bury-and-delete-window)
		 (const :tag "Kill buffer and delete window" :value kill-and-delete-window)
		 function)
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-resize-window nil
  "Whether to resize the `browse-mark-ring' window to fit its contents.
Value is either t, meaning yes, or a cons pair of integers,
 (MAXIMUM . MINIMUM) for the size of the window.  MAXIMUM defaults to
the window size chosen by `pop-to-buffer'; MINIMUM defaults to
`window-min-height'."
  :type '(choice (const :tag "No" nil)
		 (const :tag "Yes" t)
		 (cons (integer :tag "Maximum") (integer :tag "Minimum")))
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-separator "-------"
  "The string separating entries in the `separated' style.
See `browse-mark-ring-display-style'."
  :type 'string
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-recenter nil
  "If non-nil, then always keep the current entry at the top of the window."
  :type 'boolean
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-highlight-current-entry nil
  "If non-nil, highlight the currently selected `kill-ring' entry."
  :type 'boolean
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-highlight-inserted-item
  browse-mark-ring-highlight-current-entry
  "If non-nil, then temporarily highlight the inserted `kill-ring' entry.
The value selected controls how the inserted item is highlighted,
possible values are `solid' (highlight the inserted text for a
fixed period of time), or `pulse' (use the `pulse' library, a
part of `cedet', to fade out the highlighting gradually).
Setting this variable to the value `t' will select the default
highlighting style, which is currently `pulse'.

The variable `browse-mark-ring-inserted-item-face' contains the
face used for highlighting."
  :type '(choice (const nil) (const t) (const solid) (const pulse))
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-separator-face 'bold
  "The face in which to highlight the `browse-mark-ring-separator'."
  :type 'face
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-current-entry-face 'highlight
  "The face in which to highlight the browse kill current entry."
  :type 'face
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-inserted-item-face 'highlight
  "The face in which to highlight the inserted item."
  :type 'face
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-maximum-display-length nil
  "Whether or not to limit the length of displayed items.

If this variable is an integer, the display of `kill-ring' will be
limited to that many characters.
Setting this variable to nil means no limit."
  :type '(choice (const :tag "None" nil)
		 integer)
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-display-duplicates t
  "If non-nil, then display duplicate items in `kill-ring'."
  :type 'boolean
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-display-leftmost-duplicate t
  "When `browse-mark-ring-display-duplicates' nil,
if non-nil, then display leftmost(last) duplicate items in `kill-ring'."
  :type 'boolean
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-depropertize nil
  "If non-nil, remove text properties from `kill-ring' items.
This only changes the items for display and insertion from
`browse-mark-ring'; if you call `yank' directly, the items will be
inserted with properties."
  :type 'boolean
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-hook nil
  "A list of functions to call after `browse-mark-ring'."
  :type 'hook
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-replace-yank t
  "If non-nil, browse-mark-ring will replace just-yanked items
when it inserts its own. That is, if you call `yank', and then
`browse-mark-ring', and then insert something via
`browse-mark-ring', the yanked text that you originally inserted
will be deleted. This makes browse-mark-ring behave more like
`yank-pop'.

This doesn't change the behavior of `yank-pop' or
`browse-mark-ring-default-keybindings'. Instead, for this to take
effect, you will have to bind a key to `browse-mark-ring'
directly."
  :type 'boolean
  :group 'browse-mark-ring)

(defcustom browse-mark-ring-show-preview t
  "If non-nil, browse-mark-ring will show a preview of what the
buffer would look like if the item under point were inserted.

If you find the preview distracting, or something about your
setup leaves the preview in place after you're done with it, you
can disable it by setting this to nil."
  :type 'boolean
  :group 'browse-mark-ring)

(defvar browse-mark-ring-original-window-config nil
  "The window configuration to restore for `browse-mark-ring-quit'.")
(make-variable-buffer-local 'browse-mark-ring-original-window-config)

(defvar browse-mark-ring-original-window nil
  "The window in which chosen kill ring data will be inserted.
It is probably not a good idea to set this variable directly; simply
call `browse-mark-ring' again.")

(defvar browse-mark-ring-original-buffer nil
  "The buffer in which chosen kill ring data will be inserted.
It is probably not a good idea to set this variable directly; simply
call `browse-mark-ring' again.")

(defvar browse-mark-ring-preview-overlay nil
  "The overlay used to preview what would happen if the user
  inserted the given text.")

(defvar browse-mark-ring-this-buffer-replace-yanked-text nil
  "Whether or not to replace yanked text before an insert.")

(defvar browse-mark-ring-previous-overlay nil
  "Previous overlay within *Kill Ring* buffer.")

(defun browse-mark-ring-mouse-insert (e)
  "Insert the chosen text, and close the *Kill Ring* buffer afterwards."
  (interactive "e")
  (let* ((data (save-excursion
		 (mouse-set-point e)
		 (cons (current-buffer) (point))))
	 (buf (car data))
	 (pt (cdr data)))
    (browse-mark-ring-do-insert buf pt t)))

(if (fboundp 'fit-window-to-buffer)
    (defalias 'browse-mark-ring-fit-window 'fit-window-to-buffer)
  (defun browse-mark-ring-fit-window (window max-height min-height)
    (setq min-height (or min-height window-min-height))
    (setq max-height (or max-height (- (frame-height) (window-height) 1)))
    (let* ((window-min-height min-height)
	   (windows (count-windows))
	   (config (current-window-configuration)))
      (enlarge-window (- max-height (window-height)))
      (when (> windows (count-windows))
	(set-window-configuration config))
      (if (/= (point-min) (point-max))
	  (shrink-window-if-larger-than-buffer window)
	(shrink-window (- (window-height) window-min-height))))))

(defun browse-mark-ring-resize-window ()
  (when browse-mark-ring-resize-window
    (apply #'browse-mark-ring-fit-window (selected-window)
	   (if (consp browse-mark-ring-resize-window)
	       (list (car browse-mark-ring-resize-window)
		     (or (cdr browse-mark-ring-resize-window)
			 window-min-height))
	     (list nil window-min-height)))))

(defun browse-mark-ring-undo-other-window ()
  "Undo the most recent change in the other window's buffer.
You most likely want to use this command for undoing an insertion of
yanked text from the *Kill Ring* buffer."
  (interactive)
  (with-current-buffer (window-buffer browse-mark-ring-original-window)
    (undo)))

(defun browse-mark-ring-insert (&optional quit)
  "Insert the kill ring item at point into the last selected buffer.
If optional argument QUIT is non-nil, close the *Kill Ring* buffer as
well."
  (interactive "P")
  (browse-mark-ring-do-insert (current-buffer)
			      (point)
			      quit))

(defun browse-mark-ring-insert-new (insert-action post-action &optional quit)
  "Insert the kill ring item at point into the last selected buffer.
`insert-action' can be 'insert 'append 'prepend.
`post-action' can be nil 'move 'delete.
If optional argument QUIT is non-nil, close the *Kill Ring* buffer as
well."
  (interactive "P")
  (let* ((buf (current-buffer))
	(pt (point))
	(str (browse-mark-ring-current-string buf pt)))
    (cl-case insert-action
      ('insert (browse-mark-ring-do-insert buf pt nil))
      ('append (browse-mark-ring-do-append-insert buf pt nil))
      ('prepend (browse-mark-ring-do-prepend-insert buf pt nil))
      (t (error "Unknown insert-action: %s" insert-action)))
    (cl-case post-action
      ('move
	(browse-mark-ring-delete)
	(kill-new str))
      ('delete (browse-mark-ring-delete))
      (t (error "Unknown post-action: %s" post-action)))
    (if quit
      (browse-mark-ring-quit)
      (browse-mark-ring-update))))

(defun browse-mark-ring-insert-and-delete (&optional quit)
  "Insert the kill ring item at point, and remove it from the kill ring.
If optional argument QUIT is non-nil, close the *Kill Ring* buffer as
well."
  (interactive "P")
  (browse-mark-ring-do-insert (current-buffer)
			      (point)
			      quit)
  (browse-mark-ring-delete))

(defun browse-mark-ring-insert-and-quit ()
  "Like `browse-mark-ring-insert', but close the *Kill Ring* buffer afterwards."
  (interactive)
  (browse-mark-ring-insert t))

(defun browse-mark-ring-insert-and-move (&optional quit)
  "Like `browse-mark-ring-insert', but move the entry to the front."
  (interactive "P")
  (let ((buf (current-buffer))
	(pt (point)))
    (browse-mark-ring-do-insert buf pt quit)
    (let ((str (browse-mark-ring-current-string buf pt)))
      (browse-mark-ring-delete)
      (kill-new str)))
  (unless quit
    (browse-mark-ring-update)))

(defun browse-mark-ring-insert-move-and-quit ()
  "Like `browse-mark-ring-insert-and-move', but close the *Kill Ring* buffer."
  (interactive)
  (browse-mark-ring-insert-new 'insert 'move t))

(defun browse-mark-ring-prepend-insert (&optional quit)
  "Like `browse-mark-ring-insert', but it places the entry at the beginning
of the buffer as opposed to point.  Point is left unchanged after inserting."
  (interactive "P")
  (browse-mark-ring-do-prepend-insert (current-buffer)
				      (point)
				      quit))

(defun browse-mark-ring-prepend-insert-and-quit ()
  "Like `browse-mark-ring-prepend-insert', but close the *Kill Ring* buffer."
  (interactive)
  (browse-mark-ring-prepend-insert t))

(defun browse-mark-ring-prepend-insert-and-move (&optional quit)
  "Like `browse-mark-ring-prepend-insert', but move the entry to the front
of the *Kill Ring*."
  (interactive "P")
  (let ((buf (current-buffer))
	(pt (point)))
    (browse-mark-ring-do-prepend-insert buf pt quit)
    (let ((str (browse-mark-ring-current-string buf pt)))
      (browse-mark-ring-delete)
      (kill-new str)))
  (unless quit
    (browse-mark-ring-update)))

(defun browse-mark-ring-prepend-insert-move-and-quit ()
  "Like `browse-mark-ring-prepend-insert-and-move', but close the
*Kill Ring* buffer."
  (interactive)
  (browse-mark-ring-prepend-insert-and-move t))

(defun browse-mark-ring-highlight-inserted (start end)
  (when browse-mark-ring-highlight-inserted-item
    ;; First, load the `pulse' library if needed.
    (when (or (eql browse-mark-ring-highlight-inserted-item 'pulse)
	      (eql browse-mark-ring-highlight-inserted-item 't))
      (unless (and (require 'pulse nil t)
		   (fboundp 'pulse-momentary-highlight-region))
	(warn "Unable to load `pulse' library")
	(setq browse-mark-ring-highlight-inserted-item 'solid)))

    (cl-case browse-mark-ring-highlight-inserted-item
      ((pulse t)
       (let ((pulse-delay .05) (pulse-iterations 10))
	 (with-no-warnings
	   (pulse-momentary-highlight-region
	  start end browse-mark-ring-inserted-item-face))))
      ('solid
       (let ((o (make-overlay start end)))
	 (overlay-put o 'face browse-mark-ring-inserted-item-face)
	 (sit-for 0.5)
	 (delete-overlay o))))))

(defmacro browse-mark-ring-prepare-to-insert (quit &rest body)
  "Restore window and buffer ready to insert `kill-ring' item.
Temporarily restore `browse-mark-ring-original-window' and
`browse-mark-ring-original-buffer' then evaluate BODY."
  `(progn
     (if ,quit
	 (browse-mark-ring-quit)
       (browse-mark-ring-clear-preview))
     (with-selected-window browse-mark-ring-original-window
       (with-current-buffer browse-mark-ring-original-buffer
	 (progn ,@body)
	 (unless ,quit
	   (browse-mark-ring-setup-preview-overlay
	    (current-buffer)))))))

(defun browse-mark-ring-insert-and-highlight (str)
  "Helper function to insert text at point, highlighting it if appropriate."
      (let ((before-insert (point)))
	(let (deactivate-mark)
	  (insert-for-yank str))
	(browse-mark-ring-highlight-inserted
	 before-insert
	 (point))))

(defun browse-mark-ring-do-prepend-insert (buf pt quit)
  (let ((str (browse-mark-ring-current-string buf pt)))
    (browse-mark-ring-prepare-to-insert
     quit
     (save-excursion
       (goto-char (point-min))
       (browse-mark-ring-insert-and-highlight str)))))

(defun browse-mark-ring-append-insert (&optional quit)
  "Like `browse-mark-ring-insert', but places the entry at the end of the
buffer as opposed to point.  Point is left unchanged after inserting."
  (interactive "P")
  (browse-mark-ring-do-append-insert (current-buffer)
				     (point)
				     quit))

(defun browse-mark-ring-append-insert-and-quit ()
  "Like `browse-mark-ring-append-insert', but close the *Kill Ring* buffer."
  (interactive)
  (browse-mark-ring-append-insert t))

(defun browse-mark-ring-append-insert-and-move (&optional quit)
  "Like `browse-mark-ring-append-insert', but move the entry to the front
of the *Kill Ring*."
  (interactive "P")
  (let ((buf (current-buffer))
	(pt (point)))
    (browse-mark-ring-do-append-insert buf pt quit)
    (let ((str (browse-mark-ring-current-string buf pt)))
      (browse-mark-ring-delete)
      (kill-new str)))
  (unless quit
    (browse-mark-ring-update)))

(defun browse-mark-ring-append-insert-move-and-quit ()
  "Like `browse-mark-ring-append-insert-and-move', but close the
*Kill Ring* buffer."
  (interactive)
  (browse-mark-ring-append-insert-and-move t))

(defun browse-mark-ring-do-append-insert (buf pt quit)
  (let ((str (browse-mark-ring-current-string buf pt)))
    (browse-mark-ring-prepare-to-insert
     quit
     (save-excursion
       (goto-char (point-max))
       (browse-mark-ring-insert-and-highlight str)))))

(defun browse-mark-ring-delete ()
  "Remove the item at point from the `kill-ring'."
  (interactive)
  (forward-line 0)
  (unwind-protect
    (let* ((over (browse-mark-ring-target-overlay-at (point)))
	   (target (overlay-get over 'browse-mark-ring-target))
	   (inhibit-read-only t))
      (delete-region (overlay-start over) (1+ (overlay-end over)))
      (setq kill-ring (delete target kill-ring))
      (if (equal target (car kill-ring-yank-pointer))
	  (setq kill-ring-yank-pointer
		(delete target kill-ring-yank-pointer)))
      (cond
       ;; Don't try to delete anything else in an empty buffer.
       ((and (bobp) (eobp)) t)
       ;; The last entry was deleted, remove the preceeding separator.
       ((eobp)
	(progn
	  (browse-mark-ring-forward -1)
	  (let ((over (browse-mark-ring-target-overlay-at (point))))
	    (delete-region (1+ (overlay-end over)) (point-max)))))
       ;; Deleted a middle entry, delete following separator.
       ((get-text-property (point) 'browse-mark-ring-extra)
	(let ((prev (previous-single-property-change (point) 'browse-mark-ring-extra))
	      (next (next-single-property-change (point) 'browse-mark-ring-extra)))
	  (when prev (cl-incf prev))
	  (when next (cl-incf next))
	  (delete-region (or prev (point-min)) (or next (point-max))))))))
  (browse-mark-ring-resize-window)
  (browse-mark-ring-forward 0))

;; code from browse-mark-ring+.el
(defun browse-mark-ring-target-overlay-at (position &optional no-error)
  "Return overlay at POSITION that has property `browse-mark-ring-target'.
If no such overlay, raise an error unless NO-ERROR is true, in which
case return nil."
  (let ((ovs  (overlays-at (point))))
    (catch 'browse-mark-ring-target-overlay-at
      (dolist (ov  ovs)
	(when (overlay-get ov 'browse-mark-ring-target)
	  (throw 'browse-mark-ring-target-overlay-at ov)))
      (unless no-error
	(error "No selection-ring item here")))))

;; Find the string to insert at the point by looking for the overlay.
(defun browse-mark-ring-current-string (buf pt &optional no-error)
  (let ((o (browse-mark-ring-target-overlay-at pt t)))
    (if o
	(overlay-get o 'browse-mark-ring-target)
      (unless no-error
	(error "No kill ring item here")))))

(defun browse-mark-ring-do-insert (buf pt quit)
  (let ((str (browse-mark-ring-current-string buf pt)))
    (setq kill-ring-yank-pointer
	  (browse-mark-ring-current-kill-ring-yank-pointer buf pt))
    (browse-mark-ring-prepare-to-insert
     quit
     (when browse-mark-ring-this-buffer-replace-yanked-text
       (delete-region (mark) (point)))
     (when (and delete-selection-mode
		(not buffer-read-only)
		transient-mark-mode mark-active)
       (delete-active-region))
     (browse-mark-ring-insert-and-highlight str))))

(defun browse-mark-ring-update-highlighed-entry ()
  (when browse-mark-ring-highlight-current-entry
    (browse-mark-ring-update-highlighed-entry-1)))

(defun browse-mark-ring-clear-highlighed-entry ()
  (when browse-mark-ring-previous-overlay
    (cl-assert (overlayp browse-mark-ring-previous-overlay))
    (overlay-put browse-mark-ring-previous-overlay 'face nil)))

(defun browse-mark-ring-update-highlighed-entry-1 ()
  (let ((current-overlay (browse-mark-ring-target-overlay-at (point) t)))
    (cl-case current-overlay
      ;; No overlay at point.  Just clear all current highlighting.
      ((nil) (browse-mark-ring-clear-highlighed-entry))
      ;; Still on the previous overlay.
      (browse-mark-ring-previous-overlay t)
      ;; Otherwise, we've changed overlay.  Clear current
      ;; highlighting, and highlight the new overlay.
      (t
       (cl-assert (overlay-get current-overlay
			    'browse-mark-ring-target) t)
       (browse-mark-ring-clear-highlighed-entry)
       (setq browse-mark-ring-previous-overlay current-overlay)
       (overlay-put current-overlay 'face
		    browse-mark-ring-current-entry-face)))))

(defun browse-mark-ring-forward (&optional arg)
  "Move forward by ARG `kill-ring' entries."
  (interactive "p")
  (beginning-of-line)
  (while (not (zerop arg))
    (let ((o (browse-mark-ring-target-overlay-at (point) t)))
      (if (< arg 0)
	  (progn
	    (cl-incf arg)
	    (when o
	      (goto-char (overlay-start o))
	      (setq o nil))
	    (while (not (or o (bobp)))
	      (goto-char (previous-overlay-change (point)))
	      (setq o (browse-mark-ring-target-overlay-at (point) t))))
	(progn
	  (cl-decf arg)
	  ;; We're on a browse-mark-ring overlay, skip to the end of it.
	  (when o
	    (goto-char (overlay-end o))
	    (setq o nil))
	  (while (not (or o (eobp)))
	    (goto-char (next-overlay-change (point)))
	    (setq o (browse-mark-ring-target-overlay-at (point) t)))))))
  (when browse-mark-ring-recenter
    (recenter 1)))

(defun browse-mark-ring-previous (&optional arg)
  "Move backward by ARG `kill-ring' entries."
  (interactive "p")
  (browse-mark-ring-forward (- arg)))

(defun browse-mark-ring-read-regexp (msg &optional empty-is-nil-p)
  (let* ((default (car regexp-history))
	 (input
	  (read-from-minibuffer
	   (if (and default (not empty-is-nil-p))
	       (format "%s for regexp (default `%s'): "
		       msg
		       default)
	     (format "%s (regexp): " msg))
	   nil
	   nil
	   nil
	   'regexp-history
	   (if empty-is-nil-p default nil))))
    (if (equal input "")
	(if empty-is-nil-p nil default)
      input)))

(defun browse-mark-ring-search-forward (regexp &optional backwards)
  "Move to the next `kill-ring' entry matching REGEXP from point.
If optional arg BACKWARDS is non-nil, move to the previous matching
entry."
  (interactive
   (list (browse-mark-ring-read-regexp "Search forward")
	 current-prefix-arg))
  (let ((orig (point)))
    (browse-mark-ring-forward (if backwards -1 1))
    (let ((over (browse-mark-ring-target-overlay-at (point) t)))
      (while (and over
		  (not (if backwards (bobp) (eobp)))
		  (not (string-match regexp
				     (overlay-get over
						  'browse-mark-ring-target))))
	(browse-mark-ring-forward (if backwards -1 1))
	(setq over (browse-mark-ring-target-overlay-at (point) t)))
      (unless (and over
		   (string-match regexp
				 (overlay-get over
					      'browse-mark-ring-target)))
	(progn
	  (goto-char orig)
	  (message "No more `kill-ring' entries matching %s" regexp))))))

(defun browse-mark-ring-search-backward (regexp)
  "Move to the previous `kill-ring' entry matching REGEXP from point."
  (interactive
   (list (browse-mark-ring-read-regexp "Search backward")))
  (browse-mark-ring-search-forward regexp t))

(defun browse-mark-ring-quit ()
  "Take the action specified by `browse-mark-ring-quit-action'."
  (interactive)
  (browse-mark-ring-cleanup-on-exit)
  (cl-case browse-mark-ring-quit-action
    (save-and-restore
      (if (< emacs-major-version 24)
	(let (buf (current-buffer))
	     (set-window-configuration browse-mark-ring-original-window-config)
	   (kill-buffer buf))
       (quit-window)))
    (kill-and-delete-window
     (kill-buffer (current-buffer))
     (unless (= (count-windows) 1)
       (delete-window)))
    (bury-and-delete-window
     (bury-buffer)
     (unless (= (count-windows) 1)
       (delete-window)))
    (t
     (funcall browse-mark-ring-quit-action))))

(put 'browse-mark-ring-mode 'mode-class 'special)
(define-derived-mode browse-mark-ring-mode fundamental-mode
  "Kill Ring"
  "A major mode for browsing the `kill-ring'.
You most likely do not want to call `browse-mark-ring-mode' directly; use
`browse-mark-ring' instead.

\\{browse-mark-ring-mode-map}"
  ;; Later versions of emacs reduced the number of arguments to
  ;; font-lock-defaults, at least version 24 requires 5 arguments
  ;; before setting up buffer local variables.
  (set (make-local-variable 'font-lock-defaults)
       '(nil t nil nil nil
	     (font-lock-fontify-region-function . browse-mark-ring-fontify-region)))
  (define-key browse-mark-ring-mode-map (kbd "q") 'browse-mark-ring-quit)
  (define-key browse-mark-ring-mode-map (kbd "C-g") 'browse-mark-ring-quit)
  (define-key browse-mark-ring-mode-map (kbd "U") 'browse-mark-ring-undo-other-window)
  (define-key browse-mark-ring-mode-map (kbd "d") 'browse-mark-ring-delete)
  (define-key browse-mark-ring-mode-map (kbd "s") 'browse-mark-ring-search-forward)
  (define-key browse-mark-ring-mode-map (kbd "r") 'browse-mark-ring-search-backward)
  (define-key browse-mark-ring-mode-map (kbd "g") 'browse-mark-ring-update)
  (define-key browse-mark-ring-mode-map (kbd "l") 'browse-mark-ring-occur)
  (define-key browse-mark-ring-mode-map (kbd "e") 'browse-mark-ring-edit)
  (define-key browse-mark-ring-mode-map (kbd "n") 'browse-mark-ring-forward)
  (define-key browse-mark-ring-mode-map (kbd "p") 'browse-mark-ring-previous)
  (define-key browse-mark-ring-mode-map [(mouse-2)] 'browse-mark-ring-mouse-insert)
  (define-key browse-mark-ring-mode-map (kbd "?") 'describe-mode)
  (define-key browse-mark-ring-mode-map (kbd "h") 'describe-mode)
  (define-key browse-mark-ring-mode-map (kbd "y") 'browse-mark-ring-insert)
  (define-key browse-mark-ring-mode-map (kbd "u") 'browse-mark-ring-insert-move-and-quit)
  (define-key browse-mark-ring-mode-map (kbd "M-<return>") 'browse-mark-ring-insert-move-and-quit)
  (define-key browse-mark-ring-mode-map (kbd "i") 'browse-mark-ring-insert)
  (define-key browse-mark-ring-mode-map (kbd "o") 'browse-mark-ring-insert-and-move)
  (define-key browse-mark-ring-mode-map (kbd "x") 'browse-mark-ring-insert-and-delete)
  (define-key browse-mark-ring-mode-map (kbd "RET") 'browse-mark-ring-insert-and-quit)
  (define-key browse-mark-ring-mode-map (kbd "b") 'browse-mark-ring-prepend-insert)
  (define-key browse-mark-ring-mode-map (kbd "a") 'browse-mark-ring-append-insert))

;;;###autoload
(defun browse-mark-ring-default-keybindings ()
  "Set up M-y (`yank-pop') so that it can invoke `browse-mark-ring'.
Normally, if M-y was not preceeded by C-y, then it has no useful
behavior.  This function sets things up so that M-y will invoke
`browse-mark-ring'."
  (interactive)
  (defadvice yank-pop (around kill-ring-browse-maybe (arg))
    "If last action was not a yank, run `browse-mark-ring' instead."
    ;; yank-pop has an (interactive "*p") form which does not allow
    ;; it to run in a read-only buffer.  We want browse-mark-ring to
    ;; be allowed to run in a read only buffer, so we change the
    ;; interactive form here.  In that case, we need to
    ;; barf-if-buffer-read-only if we're going to call yank-pop with
    ;; ad-do-it
    (interactive "p")
    (if (not (eq last-command 'yank))
	(browse-mark-ring)
      (barf-if-buffer-read-only)
      ad-do-it))
  (ad-activate 'yank-pop))

(define-derived-mode browse-mark-ring-edit-mode fundamental-mode
  "Kill Ring Edit"
  "A major mode for editing a `kill-ring' entry.
You most likely do not want to call `browse-mark-ring-edit-mode'
directly; use `browse-mark-ring' instead.

\\{browse-mark-ring-edit-mode-map}"
  (define-key browse-mark-ring-edit-mode-map
    (kbd "C-c C-c") 'browse-mark-ring-edit-finish)
  (define-key browse-mark-ring-edit-mode-map
    (kbd "C-c C-k") 'browse-mark-ring-edit-abort)
  (define-key browse-mark-ring-edit-mode-map
    (kbd "C-g") 'browse-mark-ring-edit-abort))

(defvar browse-mark-ring-edit-target nil)
(make-variable-buffer-local 'browse-mark-ring-edit-target)

(defun browse-mark-ring-edit ()
  "Edit the `kill-ring' entry at point."
  (interactive)
  (let* ((over (browse-mark-ring-target-overlay-at (point)))
	 (target (overlay-get over 'browse-mark-ring-target))
	 (target-cell (member target kill-ring)))
    (unless target-cell
      (error "Item deleted from the kill-ring"))
    (switch-to-buffer (get-buffer-create "*Kill Ring Edit*"))
    (setq buffer-read-only nil)
    (erase-buffer)
    (insert target)
    (goto-char (point-min))
    (browse-mark-ring-resize-window)
    (browse-mark-ring-edit-mode)
    (setq header-line-format
	  '(:eval
	    (substitute-command-keys
	     "Edit, then \\[browse-mark-ring-edit-finish] to \
update entry and quit -- \\[browse-mark-ring-edit-abort] to abort.")))
    (when browse-mark-ring-show-preview
      (add-hook 'post-command-hook
		'browse-mark-ring-preview-update-for-edit nil t))
    (setq browse-mark-ring-edit-target target-cell)))

(defun browse-mark-ring-edit-finalise (entry)
  "Common code called after `browse-mark-ring-edit' has finished

This common code is called after `browse-mark-ring-edit-finish'
and `browse-mark-ring-edit-abort'.  It kills the edit buffer, and
reselects ENTRY in the `*Kill Ring*' buffer."
  ;; Kill the edit buffer.  Maybe we should do more to keep track of
  ;; the edit buffer so we can kill it even if we're not in it?
  (when (eq major-mode 'browse-mark-ring-edit-mode)
    (kill-buffer))
  ;; The user might have rearranged the windows
  (when (eq major-mode 'browse-mark-ring-mode)
    (browse-mark-ring-setup (current-buffer)
			    browse-mark-ring-original-buffer
			    browse-mark-ring-original-window
			    nil
			    browse-mark-ring-original-window-config)
    (browse-mark-ring-resize-window)
    (when entry
      (browse-mark-ring-find-entry entry))))

(defun browse-mark-ring-edit-finish ()
  "Commit the edit changes to the `kill-ring'."
  (interactive)
  (unless browse-mark-ring-edit-target
    (error "Not editing a kill-ring item"))
  (let* ((updated-entry (buffer-string))
	 (delete-entry? (string= updated-entry ""))
	 (current-entry browse-mark-ring-edit-target)
	 (select-entry nil))
    (setq browse-mark-ring-edit-target nil)
    (if delete-entry?
	;; Find the previous entry in the list to select, then
	;; delete the entry that was just edited to empty.
	(progn
	  (setq select-entry
		(cadr current-entry))
	  (setq kill-ring
		(delete (car current-entry) kill-ring))
	  (unless select-entry
	    (setq select-entry (car (last kill-ring)))))
      ;; Update the entry that was just edited, and arrange to select
      ;; it.
      (setcar current-entry updated-entry)
      (setq select-entry updated-entry))
    (browse-mark-ring-edit-finalise select-entry)))

(defun browse-mark-ring-edit-abort ()
  "Abort the edit of the `kill-ring' item."
  (interactive)
  (let ((current-entry (if browse-mark-ring-edit-target
			   (car browse-mark-ring-edit-target)
			 nil)))
    (setq browse-mark-ring-edit-target nil)
    (browse-mark-ring-edit-finalise current-entry)))

(defmacro browse-mark-ring-add-overlays-for (item &rest body)
  (let ((beg (cl-gensym "browse-mark-ring-add-overlays-"))
	(end (cl-gensym "browse-mark-ring-add-overlays-")))
    `(let ((,beg (point))
	   (,end
	    (progn
	      ,@body
	      (point))))
       (let ((o (make-overlay ,beg ,end)))
	 (overlay-put o 'browse-mark-ring-target ,item)
	 (overlay-put o 'mouse-face 'highlight)))))
;; (put 'browse-mark-ring-add-overlays-for 'lisp-indent-function 1)

(defun browse-mark-ring-elide (marker)
  (concat (buffer-name  (marker-buffer marker))
	  " at "
	  (number-to-string (marker-position marker))))

(defun browse-mark-ring-insert-as-one-line (items)
  (dolist (item items)
    (browse-mark-ring-add-overlays-for item
      (let* ((item (browse-mark-ring-elide item))
	     (len (length item))
	     (start 0)
	     (newl (propertize "\\n" 'browse-mark-ring-extra t)))
	(while (and (< start len)
		    (string-match "\n" item start))
	  (insert (substring item start (match-beginning 0))
		  newl)
	  (setq start (match-end 0)))
	(insert (substring item start len))))
    (insert "\n")))

(defun browse-mark-ring-insert-as-separated (items)
  (while (cdr items)
    (browse-mark-ring-insert-as-separated-1 (car items) t)
    (setq items (cdr items)))
  (when items
    (browse-mark-ring-insert-as-separated-1 (car items) nil)))

(defun browse-mark-ring-insert-as-separated-1 (origitem separatep)
  (let* ((item (browse-mark-ring-elide origitem)))
    (browse-mark-ring-add-overlays-for origitem
				       (insert item))
    ;; When the kill-ring has items with read-only text property at
    ;; **the end of** string, browse-mark-ring-setup fails with error
    ;; `Text is read-only'.  So inhibit-read-only here.
    ;; See http://bugs.debian.org/225082
    ;; - INOUE Hiroyuki <dombly@kc4.so-net.ne.jp>
    (let ((inhibit-read-only t))
      (insert "\n")
      (when separatep
	(insert (propertize browse-mark-ring-separator
					     'browse-mark-ring-extra t
					     'browse-mark-ring-separator t))
	(insert "\n")))))

(defun browse-mark-ring-occur (regexp)
  "Display all `kill-ring' entries matching REGEXP."
  (interactive
   (list (browse-mark-ring-read-regexp
	  "Display kill ring entries matching" t)))
  (cl-assert (eq major-mode 'browse-mark-ring-mode))
  (browse-mark-ring-setup (current-buffer)
			  browse-mark-ring-original-buffer
			  browse-mark-ring-original-window
			  regexp)
  (browse-mark-ring-resize-window))

(defun browse-mark-ring-fontify-on-property (prop face beg end)
  (save-excursion
    (goto-char beg)
    (let ((prop-end nil))
      (while
	  (setq prop-end
		(let ((prop-beg (or (and (get-text-property (point) prop) (point))
				    (next-single-property-change (point) prop nil end))))
		  (when (and prop-beg (not (= prop-beg end)))
		    (let ((prop-end (next-single-property-change prop-beg prop nil end)))
		      (when (and prop-end (not (= prop-end end)))
			(put-text-property prop-beg prop-end 'face face)
			prop-end)))))
	(goto-char prop-end)))))

(defun browse-mark-ring-fontify-region (beg end &optional verbose)
  (when verbose (message "Fontifying..."))
  (let ((buffer-read-only nil))
    (browse-mark-ring-fontify-on-property 'browse-mark-ring-extra 'bold beg end)
    (browse-mark-ring-fontify-on-property 'browse-mark-ring-separator
					  browse-mark-ring-separator-face beg end)
    (font-lock-fontify-keywords-region beg end verbose))
  (when verbose (message "Fontifying...done")))

(defun browse-mark-ring-update ()
  "Update the buffer to reflect outside changes to `kill-ring'."
  (interactive)
  (cl-assert (eq major-mode 'browse-mark-ring-mode))
  (browse-mark-ring-setup (current-buffer)
			  browse-mark-ring-original-buffer
			  browse-mark-ring-original-window)
  (browse-mark-ring-resize-window))

(defun browse-mark-ring-preview-update-text (preview-text)
  "Update `browse-mark-ring-preview-overlay' to show `PREVIEW-TEXT`."
  ;; If preview-text is nil, replacement should be nil too.
  (cl-assert (overlayp browse-mark-ring-preview-overlay))
  (let ((replacement (when preview-text
		       (propertize preview-text 'face 'highlight))))
    (overlay-put browse-mark-ring-preview-overlay
		 'before-string replacement)))

(defun browse-mark-ring-preview-update-by-position (&optional pt)
  "Update `browse-mark-ring-preview-overlay' to match item at PT.
This function is called whenever the selection in the `*Kill
Ring*' buffer is adjusted, the `browse-mark-ring-preview-overlay'
is updated to preview the text of the selection at PT (or the
current point if not specified)."
  (let ((new-text (browse-mark-ring-current-string
		   (current-buffer) (or pt (point)) t)))
    (browse-mark-ring-preview-update-text new-text)))

(defun browse-mark-ring-preview-update-for-edit ()
  "Update `browse-mark-ring-preview-overlay' after edits.
Callback triggered after a change in the *Kill Ring Edit* buffer,
update the preview in the original buffer."
  (browse-mark-ring-preview-update-text (buffer-string)))

(defun browse-mark-ring-current-index (buf pt)
  "Return current index."
  (let ((overlay-start-point
	 (overlay-start
	  (browse-mark-ring-target-overlay-at pt t)))
	(current-index 0)
	(stop-search nil)
	current-overlay-start-point)
    (save-excursion
      (goto-char (point-min))
      (while (not stop-search)
	(setq current-overlay-start-point
	      (overlay-start
	       (browse-mark-ring-target-overlay-at (point))))
	(if (eq overlay-start-point current-overlay-start-point)
	    (setq stop-search t))
	(if (not stop-search)
	  (progn
	    (browse-mark-ring-forward 1)
	    (setq current-index (1+ current-index))))))
    current-index))

(defun browse-mark-ring-current-kill-ring-yank-pointer (buf pt)
  "Return current kill-ring-yank-pointer."
  (let ((result-yank-pointer kill-ring)
	(current-string (browse-mark-ring-current-string buf pt))
	(found nil)
	(i 0))
    (if browse-mark-ring-display-duplicates
      (setq result-yank-pointer (nthcdr (browse-mark-ring-current-index buf pt) kill-ring))
      (if browse-mark-ring-display-leftmost-duplicate
	;; search leftmost duplicate
	(while (< i (length kill-ring))
	  (if (and (not found) (equal (substring-no-properties current-string) (substring-no-properties (elt kill-ring i))))
	    (progn
	      (setq result-yank-pointer (nthcdr i kill-ring))
	      (setq found t)))
	  (setq i (1+ i)))
	;; search rightmost duplicate
	(setq i (1- (length kill-ring)))
	(while (<= 0 i)
	  (if (and (not found) (equal (substring-no-properties current-string) (substring-no-properties (elt kill-ring i))))
	    (progn
	      (setq result-yank-pointer (nthcdr i kill-ring))
	      (setq found t)))
	  (setq i (1- i)))))
    result-yank-pointer))

(defun browse-mark-ring-clear-preview ()
  (when browse-mark-ring-preview-overlay
    (delete-overlay browse-mark-ring-preview-overlay)))

(defun browse-mark-ring-cleanup-on-exit ()
  "Function called when the user is finished with `browse-mark-ring'.
This function performs any cleanup that is required when the user
has finished interacting with the `*Kill Ring*' buffer.  For now
the only cleanup performed is to remove the preview overlay, if
it's turned on."
  (browse-mark-ring-clear-preview))

(defun browse-mark-ring-setup-preview-overlay (orig-buf)
  (with-current-buffer orig-buf
    (let* ((will-replace
	   (or browse-mark-ring-this-buffer-replace-yanked-text
	       (region-active-p)))
	   (start (if will-replace
		      (min (point) (mark))
		    (point)))
	   (end (if will-replace
		    (max (point) (mark))
		  (point))))
      (when browse-mark-ring-show-preview
	(browse-mark-ring-clear-preview)
	(setq browse-mark-ring-preview-overlay
	      (make-overlay start end orig-buf))
	(overlay-put browse-mark-ring-preview-overlay
		     'invisible t)))))

(defun browse-mark-ring-setup (kill-buf orig-buf window &optional regexp window-config)
  (setq browse-mark-ring-this-buffer-replace-yanked-text
	(and
	 browse-mark-ring-replace-yank
	 (or (eq last-command 'set-mark-command)
	     (eq last-command 'pop-global-mark))))
  (browse-mark-ring-setup-preview-overlay orig-buf)
  (with-current-buffer kill-buf
    (unwind-protect
	(progn
	  (browse-mark-ring-mode)
	  (setq buffer-read-only nil)
	  (when (eq browse-mark-ring-display-style
		    'one-line)
	    (setq truncate-lines t))
	  (let ((inhibit-read-only t))
	    (erase-buffer))
	  (setq browse-mark-ring-original-buffer orig-buf
		browse-mark-ring-original-window window
		browse-mark-ring-original-window-config
		(or window-config
		    (current-window-configuration)))
	  (let ((browse-mark-ring-maximum-display-length
		 (if (and browse-mark-ring-maximum-display-length
			  (<= browse-mark-ring-maximum-display-length 3))
		     4
		   browse-mark-ring-maximum-display-length))
		(items (save-excursion (switch-to-buffer orig-buf) mark-ring)))
	    (when (not browse-mark-ring-display-duplicates)
	      ;; display leftmost or rightmost duplicate.
	      ;; if `browse-mark-ring-display-leftmost-duplicate' is t,
	      ;; display leftmost(last) duplicate.
	      (cl-delete-duplicates items
				 :test #'equal
				 :from-end browse-mark-ring-display-leftmost-duplicate))
	    (when (stringp regexp)
	      (setq items (delq nil
				(mapcar
				 #'(lambda (item)
				     (when (string-match regexp item)
				       item))
				 items))))
	    (funcall (or (cdr (assq browse-mark-ring-display-style
				    browse-mark-ring-display-styles))
			 (error "Invalid `browse-mark-ring-display-style': %s"
				browse-mark-ring-display-style))
		     items)
	    (when browse-mark-ring-show-preview
	      (browse-mark-ring-preview-update-by-position (point-min))
	      ;; Local post-command-hook, only happens in the *Kill
	      ;; Ring* buffer
	      (add-hook 'post-command-hook
			'browse-mark-ring-preview-update-by-position
			nil t)
	      (add-hook 'kill-buffer-hook
			'browse-mark-ring-cleanup-on-exit
			nil t))
	    (when browse-mark-ring-highlight-current-entry
	      (add-hook 'post-command-hook
			'browse-mark-ring-update-highlighed-entry
			nil t))
;; Code from Michael Slass <mikesl@wrq.com>
	    (message
	     (let ((entry (if (= 1 (length kill-ring)) "entry" "entries")))
	       (concat
		(if (and (not regexp)
			 browse-mark-ring-display-duplicates)
		    (format "%s %s in the kill ring."
			    (length kill-ring) entry)
		  (format "%s (of %s) %s in the kill ring shown."
			  (length items) (length kill-ring) entry))
		(substitute-command-keys
		 (concat "    Type \\[browse-mark-ring-quit] to quit.  "
			 "\\[describe-mode] for help.")))))
;; End code from Michael Slass <mikesl@wrq.com>
	    (set-buffer-modified-p nil)
	    (goto-char (point-min))
	    (browse-mark-ring-forward 0)
	    (setq mode-name (if regexp
				(concat "Kill Ring [" regexp "]")
			      "Kill Ring"))
	    (run-hooks 'browse-mark-ring-hook)))
      (progn
	(setq buffer-read-only t)))))

(defun browse-mark-ring-find-entry (entry-string)
  "Select entry matching ENTRY-STRING in current buffer.
Helper function that should be invoked in the *Kill Ring* buffer,
move the selection forward to the entry matching ENTRY-STRING.
If there's no matching entry then leave point at the start the
start of the buffer."
  (goto-char (point-min))
  (let ((stop-search nil)
	(search-found nil)
	current-target-string)
    (while (not stop-search)
      (setq current-target-string
	    (browse-mark-ring-current-string (current-buffer) (point)))
      (if (not current-target-string)
	  (setq stop-search t)
	(if (equal current-target-string entry-string)
	    (progn
	      (setq search-found t)
	      (setq stop-search t))))
      (unless stop-search
	(browse-mark-ring-forward 1)))
    (unless search-found
      (goto-char (point-min)))))

;;;###autoload
(defun browse-mark-ring ()
  "Display items in the `kill-ring' in another buffer."
  (interactive)
  (if (eq major-mode 'browse-mark-ring-mode)
      (error "Already viewing the kill ring"))

  (let* ((orig-win (selected-window))
	 (orig-buf (window-buffer orig-win))
	 (buf (get-buffer-create "*Kill Ring*"))
	 (kill-ring-yank-pointer-string
	  (if kill-ring-yank-pointer
	      (substring-no-properties (car kill-ring-yank-pointer)))))
    (browse-mark-ring-setup buf orig-buf orig-win)
    (pop-to-buffer buf)
    (browse-mark-ring-resize-window)
    (unless (eq kill-ring kill-ring-yank-pointer)
      (browse-mark-ring-find-entry kill-ring-yank-pointer-string))))

(provide 'browse-mark-ring)

;;; browse-mark-ring.el ends here
