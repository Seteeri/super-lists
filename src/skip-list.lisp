(in-package #:skip-list)

;; sbcl --eval "(progn (ql:quickload 'skip-list) (skip-list::test))"

(declaim (optimize (speed 3) (debug 0) (safety 0)))

(defconstant +e+ (exp 1)) ; Euler's number = ~2.7182817
(defconstant +1/e+ (/ 1.0 +e+))

(setf *random-state* (make-random-state t))

;; Each node contains lanes which containers pointers to other nodes 
;; on that respective level
(defstruct (node (:conc-name ne-))
  data      ; arbitrary data
  spans     ; dist to next node for each lane/level
  forwards) ; next nodes

(defstruct (skip-list (:conc-name sl-))
  height     ; max height
  length
  node-head)

(declaim (inline generate-random-level))
(defun generate-random-level (height)
  (loop
     :with level := 1 ; 0 contains all nodes so start at 1
     :while (and (< (random 1.0) +1/e+) ; p = 0.5, e=2.71828, 1/e = <-
		 (< level (1- height)))
     :do (incf level)
     :finally (return-from generate-random-level level)))

(declaim (inline make-node))
(defun init-node (height data)
  (make-node :data data
	     :spans (make-array height
				:fill-pointer nil
				:adjustable nil
				:initial-element 0)
	     :forwards (make-array height
				   :fill-pointer nil
				   :adjustable nil
				   :initial-element nil)))

(defun init-skip-list (size &optional (preallocate nil))
  (let* ((height (truncate (+ 1 (log size +e+))))
	 (skip-list (make-skip-list :height height
				    :length 0
				    :node-head (init-node height nil))))
    ;; Preallocate nodes
    (when preallocate
      (loop
	 :for i :from 0 :below size
	 :do (insert skip-list 0 nil)))
    
    skip-list))

;;;;;;;;;;;;;;;;;;;;;;;;;

;; TODO: Refactor outer loop code into loop
(defun nth (sl-list i)
  (let ((node (sl-node-head sl-list)))
    (loop
       :for level :from (1- (sl-height sl-list)) :downto 0
       :with x := -1
       :do (loop
	      :while (and (aref (ne-forwards node) level)
			  (< (+ x (aref (ne-spans node) level)) i))
	      :for spans := (ne-spans node)
	      :for forwards := (ne-forwards node)
	      :do (progn
		    (incf x (aref spans level))
		    (setf node (aref forwards level)))))
    ;; Did not find it
    (if (eq node (sl-node-head sl-list))
	nil
	node)))

;; TODO: Use setf for below instead
;; Error on missing? -> Like list, return nil
(defun get-nth-data (sl-list i)
  (let ((node (nth sl-list i)))
    (when node
      (ne-data node))))

(defun set-nth-data (sl-list i data)
  (let ((node (nth sl-list i)))
    (when node
      (setf (ne-data node) data))))

(defun insert (sl-list i data)

  ;; Create the new node then splice into existing nodes
  
  (let* ((height (sl-height sl-list))
	 (height-new (generate-random-level height))
         (node-new (init-node (+ height-new 1) data)))
    
    (incf (gethash height-new *tracker-sl*))
    
    (loop
       :for level :from (1- height) :downto 0
       :with node := (sl-node-head sl-list) :and x = -1
       :do (progn
	     
	     ;; Find the backwards node (or node@i)
	     ;; Search until node and span@level is less than index
	     (loop
		:while (and (aref (ne-forwards node) level)
			    (< (+ x (aref (ne-spans node) level)) i))
		:for spans := (ne-spans node)
		:for forwards := (ne-forwards node)
		:do (progn
		      (incf x (aref spans level))
		      (setf node (aref forwards level))))

	     ;; Increase span for backwards node to account for new node
	     (incf (aref (ne-spans node) level))

	     ;; Update nodes that are <= height of new node
	     ;; These are nodes that link to the new node
	     (when (<= level height-new)
	       
	       ;; Link new-node to previous-node's forward
	       ;; Link previous-node's forward to node-new
	       ;; Update node-new's span = prev - (new - prev)
	       ;; Update previous node's span
	       (setf (aref (ne-forwards node-new) level) (aref (ne-forwards node) level)
		     (aref (ne-forwards node) level) node-new
		     (aref (ne-spans node-new) level) (- (aref (ne-spans node) level) (- i x))
		     (aref (ne-spans node) level) (- i x)))))
    
    (incf (sl-length sl-list))
    node-new))

(defun delete (sl-list i)

  ;; Implement delete range:
  ;; - Need to decrease each span by length of range
  
  (let ((node (sl-node-head sl-list))
	(node-del nil))
    
    (loop
       :for level :from (1- (sl-height sl-list)) :downto 0
       :with x := -1
       :do (progn

	     ;; Find node@i
	     (loop
		:while (and (aref (ne-forwards node) level)
			    (< (+ x (aref (ne-spans node) level)) i))
		:for spans := (ne-spans node)
		:for forwards := (ne-forwards node)
		:do (progn
		      (incf x (aref (ne-spans node) level))
		      (setf node (aref (ne-forwards node) level))))

	     ;; Dec span by 1 @ level
	     (decf (aref (ne-spans node) level))

	     ;; Update previous node
	     (when (and (= (+ x (aref (ne-spans node) level) 1)
			   i)
			(aref (ne-forwards node) level))
	       ;; x = u.next[r].x;

	       (setf node-del (aref (ne-forwards node) level))

	       ;; Link span by span of rem node
	       (incf (aref (ne-spans node) level)
		     (aref (ne-spans (aref (ne-forwards node) level)) level))
	       ;; Link forward node to forward node of rem node
	       (setf (aref (ne-forwards node) level)
		     (aref (ne-forwards (aref (ne-forwards node) level)) level))))

       ;; Don't need this since fixed arrays are used
       ;; instead of linked lists
       ;; If prev node is sentinel then decrease max height
       ;; (when (and (equal node (sl-node-head sl-list))
       ;; 		  (aref (ne-forwards node) level))
       ;; 	 (decf (sl-height sl-list)))

       ;; Decrease when found = x is i-1
       :finally (when (and node
			   (= x (1- i))
			   (not (eq node (sl-node-head sl-list))))
		  (decf (sl-length sl-list))))
    
    node-del))

(defmacro doskiplist ((var skiplist) &body body)
  "Loops over the elements in `dlist', binding each to `var' in turn, then executing `body'."
  `(loop
      ;; Start at head+1
      :for node := (aref (ne-forwards (sl-node-head ,skiplist)) 0) :then (aref (ne-forwards node) 0)
      :while node
      :do (let ((,var (ne-data node)))
	    ,@body)))

(defun enqueue (sl data)
  (insert sl 0 i))

(defun dequeue (sl)
  (delete sl 0))

;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun init-sl-tracker (sl)
  (defparameter *tracker-sl* (make-hash-table :size (sl-height sl)))
  (loop :for i :from 1 :below (sl-height sl)
     :do (setf (gethash i *tracker-sl*) 0)))

(defun test ()
  ;; (declaim (optimize (speed 3) (debug 0) (safety 0)))
  
  (setf *random-state* (make-random-state t))

  ;; 16 = ~64k
  ;; 20 = 1048576
  (let* ((n (expt 2 20))
	 (sl (init-skip-list n)))

    (init-sl-tracker sl)
    
    ;; Insert at beginning
    (when t
      (format t "Insert ~a elements...~%~%" n)
      (loop
	 :for i :from n :above 0
	 :do (insert sl 0 i)))
    (format t "Length: ~a~%" (sl-length sl))

    ;; Print levels
    ;; level 0 is 100%
    (when t
      (format t "Level ~S : ~S nodes, ~a~a ~%"
	      0
	      n
	      100.0
	      #\%)
      (loop
	 :for key :being :the :hash-keys :of *tracker-sl*
	 :using (hash-value value)
	 :do (format t "Level ~S : ~S nodes, ~a~a ~%"
		     key
		     value
		     (coerce (* (/ value n) 100) 'single-float)
		     #\%)))
    
    ;; Test get-nth
    (when nil
      (dotimes (i 8)
	(time
	 (format t "nth@~a: ~a~%" 1 (get-nth-data sl n)))))

    ;; Test set-nth
    ;; TODO: Make nth zero based
    (when nil
      (format t "Before: ~a~%" (get-nth-data sl 1))
      (set-nth-data sl 1 "hello")
      (format t "After: ~a~%" (get-nth-data sl 1)))
    
    ;; Test macro
    (when nil
      (format t "DOSKIPLIST:~%")
      (dotimes (i 8)
	(time
	 (doskiplist (i sl)
		     ;; (format t "data: ~a~%" i)
		     t))))

    ;; Test iterate
    ;; Move from node to node on 0 level
    (when nil
      (dotimes (i 8)
	(time
	 ;; Iterator - make macro
	 (loop
	    :with node := (sl-node-head sl)
	    :while (aref (ne-forwards node) 0)
	    :for forwards := (ne-forwards node)
	    :do (setf node (aref forwards 0))))))

    ;; Test delete
    (when t
      (format t "Delete ~a elements...~%~%" n)
      (time
       (loop
	  :for i :from 0 :below n
	  :do (progn
		(delete sl 0)))))
      ;; (format t "~a~%" (get-nth-data sl 1))

    
    t))
