(in-package :lem)

(export '(*input-hook*
          last-read-key-sequence
          start-record-key
          stop-record-key
          key-recording-p
          read-event
          read-key
          unread-key
          read-command
          read-key-sequence
          unread-key-sequence
          execute-key-sequence
          sit-for))

(defvar *input-hook* '())

(defvar *key-recording-p* nil)
(defvar *record-keys* nil)
(defvar *unread-keys* nil)

(let (last-read-key-sequence)
  (defun last-read-key-sequence ()
    last-read-key-sequence)
  (defun set-last-read-key-sequence (key-sequence)
    (setf last-read-key-sequence key-sequence)))

(let ((key-recording-status-name " Def"))
  (defun start-record-key ()
    (modeline-add-status-list key-recording-status-name)
    (setq *key-recording-p* t)
    (setq *record-keys* nil))
  (defun stop-record-key ()
    (when *key-recording-p*
      (modeline-remove-status-list key-recording-status-name)
      (setq *key-recording-p* nil)
      (nreverse *record-keys*))))

(defun key-recording-p ()
  *key-recording-p*)

(defun read-event (&optional timeout)
  (receive-event timeout))

(defun read-key-1 ()
  (loop
    (let ((ms (get-next-timer-timing-ms)))
      (cond ((null ms)
             (loop
              (let ((e (read-event nil)))
                (when (key-p e)
                  (return-from read-key-1 e)))))
            ((minusp ms)
             (update-timer))
            (t
             (let ((e (read-event (float (/ ms 1000)))))
               (when (key-p e)
                 (return e)))
             ;; Note:
             ;;   This call of `update-timer` is essentially redundant.
             ;;   The call have effect iff `cond` of next iteration falls into `minusp` clause.
             ;;   The difference of existance of the call is, there was possibility of consecutive
             ;;   two call of `update-timer` both have effect.
             ;;   I think we should forbid this case.  It may include difficulty, e.g., for debugging.
             ;;   c.f. https://github.com/cxxxr/lem/pull/430
             ;; (update-timer)
             )))))

(defun read-key ()
  (let ((key (if (null *unread-keys*)
                 (read-key-1)
                 (pop *unread-keys*))))
    (if *key-recording-p*
        (push key *record-keys*)
        (run-hooks *input-hook* key))
    key))

(defun unread-key (key)
  (when *key-recording-p*
    (pop *record-keys*))
  (push key *unread-keys*))

(defun read-command ()
  (let* ((key (read-key))
         (cmd (lookup-keybind key))
         (kseq (list key)))
    (loop
      (cond ((hash-table-p cmd)
             (let ((key (read-key)))
               (setf kseq (nconc kseq (list key)))
               (setf cmd (lookup-keybind kseq))))
            (t
             (set-last-read-key-sequence kseq)
             (return cmd))))))

(defun read-key-sequence ()
  (read-command)
  (last-read-key-sequence))

(defun unread-key-sequence (kseq)
  (setf *unread-keys* (nconc *unread-keys* kseq)))

(defun execute-key-sequence (key-sequence)
  (let ((*unread-keys* key-sequence))
    (do-command-loop (:interactive nil)
      (when (null *unread-keys*)
        (return))
      (call-command (read-command) nil))))

(defun sit-for (seconds &optional (update-window-p t))
  (when update-window-p (redraw-display))
  (let ((e (read-event seconds)))
    (cond ((null e) t)
          ((abort-key-p e) (error 'editor-abort))
          ((key-p e) (unread-key e))
          (t nil))))
