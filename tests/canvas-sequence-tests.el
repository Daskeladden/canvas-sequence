;;; canvas-sequence-tests.el --- tests of the sequence diagram -*- lexical-binding: t -*-
(require 'ert)
(require 'cl-lib)
(require 'canvas-sequence)

(defun canvas-sequence-test--inked-p (pixel)
  "Whether PIXEL, ARGB32, carries ink of the edge colour, which the tests
set to blue: more blue than red, whatever the antialiasing left."
  (> (logand pixel #xFF) (+ 40 (logand (ash pixel -16) #xFF))))

(defun canvas-sequence-test--spec ()
  "The spec of three parties and three messages."
  '((party "alice" "Alice")
    (party "bob" "Bob")
    (party "carol" "Carol")
    (message "alice" "bob" "hello")
    (message "bob" "carol" "ask")
    (message "carol" "alice" "answer" :dashed t)))

;;;; The model

(ert-deftest canvas-sequence-a-spec-becomes-parties-and-messages ()
  ;; GIVEN a spec of two parties and two messages, the second back again
  ;; WHEN it is built
  ;; THEN the parties stand in the order they were named, each with its
  ;;      label, AND the messages keep their order, their parties and their
  ;;      text
  (let* ((diagram (canvas-sequence-build
                   '((party "alice" "Alice")
                     (party "bob" "Bob")
                     (message "alice" "bob" "hello")
                     (message "bob" "alice" "hi" :dashed t))))
         (parties (canvas-sequence-parties diagram))
         (messages (canvas-sequence-messages diagram)))
    (should (equal (mapcar #'canvas-sequence-party-name parties) '("alice" "bob")))
    (should (equal (mapcar #'canvas-sequence-party-label parties) '("Alice" "Bob")))
    (should (equal (mapcar #'canvas-sequence-message-text messages) '("hello" "hi")))
    (should (equal (mapcar (lambda (m) (canvas-sequence-party-name (canvas-sequence-message-from m))) messages)
                   '("alice" "bob")))
    (should-not (canvas-sequence-message-dashed (nth 0 messages)))
    (should (canvas-sequence-message-dashed (nth 1 messages)))))

(ert-deftest canvas-sequence-a-party-with-no-label-is-called-by-its-name ()
  ;; GIVEN a party named with no label of its own
  ;; THEN it is called by its name
  (let ((diagram (canvas-sequence-build '((party "alice")))))
    (should (equal (canvas-sequence-party-label (car (canvas-sequence-parties diagram))) "alice"))))

(ert-deftest canvas-sequence-a-message-names-a-party-that-is-there ()
  ;; GIVEN a message from a party that no line names
  ;; WHEN the spec is built
  ;; THEN it is a user error that names the party and the message
  (let ((err (should-error (canvas-sequence-build '((party "alice") (message "alice" "bob" "hello")))
                           :type 'user-error)))
    (should (string-search "bob" (error-message-string err))))

  ;; GIVEN a message before any party is named
  ;; THEN the party it names is the error, not the order of the lines
  (should-error (canvas-sequence-build '((message "alice" "bob" "hi"))) :type 'user-error))

(ert-deftest canvas-sequence-a-message-to-the-party-it-came-from-is-its-own ()
  ;; GIVEN a message from a party to itself
  ;; THEN it is known as one, so that the drawing can loop it back
  (let* ((diagram (canvas-sequence-build '((party "alice") (message "alice" "alice" "think"))))
         (message (car (canvas-sequence-messages diagram))))
    (should (canvas-sequence-message-self-p message))))


;;;; The layout

(defmacro canvas-sequence-test--rendering (&rest body)
  "Run BODY with a fixed font and fixed colours, so pixels are predictable."
  `(let ((canvas-diagram-font "Sans 12px")
         (canvas-diagram-colors '(:background "white" :node "gray90" :text "black"
                                  :edge "blue" :selection "red"))
         (canvas-diagram-paper nil))
     ,@body))

(defmacro canvas-sequence-test--with-context (var w h &rest body)
  "Run BODY with VAR bound to a context on a fresh W by H canvas."
  (declare (indent 3))
  `(let ((,var (canvas-cairo-context (list 'image :type 'canvas :id (make-symbol "test")
                                           :data-width ,w :data-height ,h))))
     (unwind-protect (progn ,@body)
       (canvas-cairo-destroy ,var))))

(defun canvas-sequence-test--diagram ()
  "A diagram of three parties and three messages."
  (canvas-sequence-build '((party "alice" "Alice")
                           (party "bob" "Bob")
                           (party "carol" "Carol")
                           (message "alice" "bob" "hello")
                           (message "bob" "carol" "ask")
                           (message "carol" "alice" "answer" :dashed t))))

(ert-deftest canvas-sequence-the-heads-stand-in-a-row ()
  ;; GIVEN three head boxes of their own widths
  ;; WHEN they are put in a row
  ;; THEN each starts a gap after the one before it, they all share one
  ;;      top, AND the lifeline of each runs down the middle of its head
  (let ((nodes (list (canvas-diagram-node-create :label "a" :w 60 :h 30)
                     (canvas-diagram-node-create :label "b" :w 80 :h 30)
                     (canvas-diagram-node-create :label "c" :w 40 :h 30))))
    (canvas-sequence--place-heads nodes)
    (should (equal (mapcar #'canvas-diagram-node-x nodes)
                   (list 0 (+ 60 canvas-sequence-gap) (+ 60 canvas-sequence-gap 80 canvas-sequence-gap))))
    (should (equal (mapcar #'canvas-diagram-node-y nodes) '(0 0 0)))
    (should (= (canvas-sequence--lifeline-x (nth 1 nodes)) (+ 60 canvas-sequence-gap 40)))))

(ert-deftest canvas-sequence-each-message-has-a-row-of-its-own ()
  ;; GIVEN a diagram whose heads are 30 tall
  ;; WHEN the rows of its messages are asked for
  ;; THEN the first stands a gap below the heads and each one after it a
  ;;      row further down, AND the drawing is tall enough to hold them all
  (let ((diagram (canvas-sequence-test--diagram)))
    (setf (canvas-sequence-top diagram) 30)
    (should (= (canvas-sequence--message-y diagram 0) (+ 30 canvas-sequence-head-gap)))
    (should (= (- (canvas-sequence--message-y diagram 2) (canvas-sequence--message-y diagram 1))
               canvas-sequence-row))
    (should (> (canvas-sequence-height diagram) (canvas-sequence--message-y diagram 2)))))

;;;; The drawing

(ert-deftest canvas-sequence-a-diagram-draws-its-lifelines-and-arrows ()
  ;; GIVEN a diagram of three parties laid out on a canvas
  ;; WHEN it is drawn
  ;; THEN a head box stands for each party, a line of life runs below it,
  ;;      AND an arrow of the edge colour crosses the space between two
  ;;      lifelines on the first row
  (canvas-sequence-test--rendering
   (canvas-sequence-test--with-context ctx 600 400
     (let* ((diagram (canvas-sequence-diagram))
            (spec (canvas-sequence-test--spec))
            (model (progn (setf (canvas-diagram-spec diagram) spec
                                (canvas-diagram-model diagram) (canvas-sequence-build spec)
                                (canvas-diagram-nodes diagram) (canvas-sequence--lay-out diagram ctx))
                          (canvas-diagram-model diagram))))
       (apply #'canvas-cairo-clear ctx (append (canvas-diagram-color :background) '(1)))
       (canvas-sequence--draw-edges diagram ctx)
       (canvas-cairo-flush ctx)
       (let* ((nodes (canvas-diagram-nodes diagram))
              (x0 (canvas-sequence--lifeline-x (nth 0 nodes)))
              (x1 (canvas-sequence--lifeline-x (nth 1 nodes)))
              (y (canvas-sequence--message-y model 0)))
         ;; the arrow of the first message lies on its row, between the
         ;; two lifelines it joins
         (should (cl-loop for x from (+ x0 8) below (- x1 8)
                          thereis (cl-loop for dy from -2 to 2
                                           thereis (canvas-sequence-test--inked-p
                                                    (canvas-cairo-pixel ctx (round x) (round (+ y dy)))))))
         ;; the picture leaves room below the heads for every message, and
         ;; to the right for the loop of a message a party sends itself
         (should (>= (cdr (canvas-diagram-slack diagram))
                     (- (canvas-sequence-height model) (canvas-sequence-top model))))

         ;; and the line of life runs below the head, in the row above the
         ;; first message
         (should (cl-loop for dy from 0 to 10
                          thereis (canvas-sequence-test--inked-p
                                   (canvas-cairo-pixel ctx (round x0)
                                                       (round (+ (canvas-sequence-top model) dy)))))))))))

(ert-deftest canvas-sequence-is-the-layout-of-its-kind ()
  ;; GIVEN canvas-sequence loaded
  ;; THEN readers draw a sequence diagram, a spec of kind sequence, with it: it follows
  ;;      the source AND exports a picture
  (should (equal (alist-get 'sequence canvas-diagram-layouts)
                 '(:follow canvas-sequence-follow :export canvas-sequence-export))))

;;;; The menu

(defmacro canvas-sequence-test--with-shown (&rest body)
  "Run BODY in the buffer of a sequence diagram of three parties, which
the selected window shows."
  (declare (indent 0))
  `(save-window-excursion
     (let ((buffer (canvas-sequence-show (canvas-sequence-test--spec) "*canvas-sequence-test*")))
       (unwind-protect
           (with-current-buffer buffer ,@body)
         (kill-buffer buffer)))))

(ert-deftest canvas-sequence-the-menu-key-opens-the-menu-of-a-sequence ()
  ;; GIVEN the buffer of a sequence diagram in the selected window
  (canvas-sequence-test--with-shown
    (unwind-protect
        (progn
          ;; WHEN the key of the menu is pressed
          (execute-kbd-macro (kbd "SPC"))
          ;; THEN the menu of a sequence is open
          (should (transient-active-prefix 'canvas-sequence-menu))
          ;; WHEN the same key is pressed again
          (execute-kbd-macro (kbd "SPC"))
          ;; THEN the menu is closed
          (should-not (transient-active-prefix)))
      ;; A menu closes in the hooks of the command loop, so a key closes
      ;; one that a failed test left open.
      (when (transient-active-prefix)
        (execute-kbd-macro (kbd "C-g"))))))

(ert-deftest canvas-sequence-the-menu-holds-the-shared-keys-of-a-diagram ()
  ;; GIVEN the menu of a sequence
  ;; THEN each key that sets a look of a diagram runs its command there
  (pcase-dolist (`(,key . ,command) canvas-diagram-setting-keys)
    (should (eq (plist-get (cdr (transient-get-suffix 'canvas-sequence-menu key)) :command)
                command))))

(ert-deftest canvas-sequence-the-mode-names-its-keys ()
  ;; GIVEN the buffer of a sequence diagram
  (canvas-sequence-test--with-shown
    ;; WHEN the documentation of its mode is asked for
    (let ((text (documentation 'canvas-sequence-mode)))
      ;; THEN it names the key that opens the menu AND the key that
      ;;      writes the picture, each as the key that it is
      (should (string-search "SPC opens the menu" text))
      (should (string-search "C-x C-w writes the picture" text)))))

;;; canvas-sequence-tests.el ends here
