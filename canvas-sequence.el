;;; canvas-sequence.el --- Sequence diagrams on an Emacs canvas -*- lexical-binding: t -*-

;; Copyright (C) 2026 canvas-sequence contributors

;; Author: Daskeladden
;; Version: 0.1.0
;; Package-Requires: ((emacs "32.0.50") (canvas-diagram "0.1.0"))
;; Keywords: multimedia, tools, convenience
;; URL: https://github.com/Daskeladden/canvas-sequence

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A sequence diagram shows who says what to whom, and in which order.
;; Each party has a box at the top and a line of life below it, and each
;; message is an arrow from one line of life to another, drawn under the
;; message before it.
;;
;; The diagram is read from a spec, a list of lines:
;;
;;   ((party "alice" "Alice")
;;    (party "bob")
;;    (message "alice" "bob" "hello")
;;    (message "bob" "alice" "hi" :dashed t))
;;
;; A party is named once, and the order of those lines is the order of
;; the columns.  A message names the party it comes from and the party it
;; goes to, either of which must be named already, and the text it
;; carries.  A message to the party it came from loops back to the same
;; line of life.
;;
;; canvas-mermaid and canvas-plantuml read their own languages into this
;; spec, so that one drawing serves both.

;;; Code:

(require 'cl-lib)
(require 'canvas-diagram)

;;;; The model

(cl-defstruct (canvas-sequence-party (:constructor canvas-sequence-party-create))
  "A party of a sequence diagram: its NAME, which the messages use, the
LABEL its box shows, and the POS it was read from, or nil."
  name label pos)

(cl-defstruct (canvas-sequence-message (:constructor canvas-sequence-message-create))
  "A message: the party it comes FROM, the party it goes TO, its TEXT,
whether its line is DASHED, and the POS it was read from, or nil."
  from to text dashed pos)

(cl-defstruct (canvas-sequence (:constructor canvas-sequence--create))
  "A sequence diagram: its PARTIES, in the order they were named, its
MESSAGES, in the order they were read, and, once it is laid out, the TOP
at which the lines of life start."
  parties messages (top 0))

(defun canvas-sequence-message-self-p (message)
  "Whether MESSAGE goes back to the party it came from."
  (eq (canvas-sequence-message-from message) (canvas-sequence-message-to message)))

(defun canvas-sequence--party-named (parties name line)
  "The party of PARTIES called NAME; a name none of them has is a user
error that names it and the LINE that asked for it."
  (or (cl-find name parties :key #'canvas-sequence-party-name :test #'equal)
      (user-error "canvas-sequence: no party is called %s, in %S" name line)))

(defun canvas-sequence--party (line)
  "The party that LINE, (party NAME [LABEL] [:pos POS]), names."
  (pcase-let ((`(,_ ,name . ,rest) line))
    (unless (stringp name)
      (user-error "canvas-sequence: a party needs a name, in %S" line))
    (let ((label (and (stringp (car rest)) (car rest))))
      (canvas-sequence-party-create :name name :label (or label name)
                                    :pos (plist-get (if label (cdr rest) rest) :pos)))))

(defun canvas-sequence--message (line parties)
  "The message that LINE, (message FROM TO TEXT . PLIST), names among
PARTIES."
  (pcase-let ((`(,_ ,from ,to ,text . ,plist) line))
    (unless (stringp text)
      (user-error "canvas-sequence: a message needs text, in %S" line))
    (canvas-sequence-message-create
     :from (canvas-sequence--party-named parties from line)
     :to (canvas-sequence--party-named parties to line)
     :text text :dashed (plist-get plist :dashed) :pos (plist-get plist :pos))))

(defun canvas-sequence-build (spec)
  "The diagram that SPEC, a list of lines, holds.
A line is (party NAME [LABEL] [:pos POS]) or (message FROM TO TEXT
[:dashed BOOL] [:pos POS]).  Anything else is a user error."
  (let (parties messages)
    (dolist (line spec)
      (pcase (car-safe line)
        ('party (push (canvas-sequence--party line) parties))
        ('message (push (canvas-sequence--message line (reverse parties)) messages))
        (_ (user-error "canvas-sequence: no line of a diagram reads %S" line))))
    (canvas-sequence--create :parties (nreverse parties) :messages (nreverse messages))))


;;;; The layout

(defconst canvas-sequence-gap 40
  "The pixels between one head box and the next.")

(defconst canvas-sequence-row 44
  "The pixels from one message to the next.")

(defconst canvas-sequence-head-gap 28
  "The pixels between the head boxes and the first message.")

(defconst canvas-sequence-foot 24
  "The pixels below the last message, where the lines of life end.")

(defconst canvas-sequence--self-out 40
  "How far a message to the party it came from reaches to the right.")

(defun canvas-sequence--place-heads (nodes)
  "Put NODES, the head boxes, in a row from the left, sharing one top; the
nodes."
  (let ((x 0))
    (dolist (node nodes nodes)
      (setf (canvas-diagram-node-x node) x
            (canvas-diagram-node-y node) 0)
      (setq x (+ x (canvas-diagram-node-w node) canvas-sequence-gap)))))

(defun canvas-sequence--lifeline-x (node)
  "The x of the line of life below NODE, a head box: its middle."
  (+ (canvas-diagram-node-x node) (/ (canvas-diagram-node-w node) 2)))

(defun canvas-sequence--message-y (diagram i)
  "The y of the message I of DIAGRAM, counting from 0."
  (+ (canvas-sequence-top diagram) canvas-sequence-head-gap (* i canvas-sequence-row)))

(defun canvas-sequence-height (diagram)
  "How tall DIAGRAM stands, with room below its last message."
  (+ (canvas-sequence--message-y diagram (max 0 (1- (length (canvas-sequence-messages diagram)))))
     canvas-sequence-foot))

(defun canvas-sequence--head-node (diagram party)
  "A head box for PARTY of DIAGRAM."
  (ignore diagram)
  ;; The kind of a node is text for the legend, and every node here is a
  ;; party, so a kind would say nothing.
  (canvas-diagram-node-create :label (canvas-sequence-party-label party)
                              :pos (canvas-sequence-party-pos party)))

(defun canvas-sequence--node-of (diagram party)
  "The head box of PARTY among DIAGRAM's nodes."
  (nth (cl-position party (canvas-sequence-parties (canvas-diagram-model diagram)))
       (canvas-diagram-nodes diagram)))

(defun canvas-sequence--self-reach (model node ctx)
  "How far to the right the loop of a message to NODE's own party reaches
in MODEL, measured on CTX; 0 when that party sends itself nothing."
  (let ((font (canvas-diagram-font))
        (party (cl-find (canvas-diagram-node-label node) (canvas-sequence-parties model)
                        :key #'canvas-sequence-party-label :test #'equal)))
    (apply #'max 0
           (mapcar (lambda (message)
                     (if (and (canvas-sequence-message-self-p message)
                              (eq (canvas-sequence-message-from message) party))
                         (+ (canvas-sequence--lifeline-x node) canvas-sequence--self-out 8
                            (car (canvas-cairo-text-size ctx (canvas-sequence-message-text message) font)))
                       0))
                   (canvas-sequence-messages model)))))

(defun canvas-sequence--slack (model nodes ctx)
  "The room (W . H) the drawing of MODEL takes beyond its head NODES: the
messages below them, and the loop of a message a party sends itself."
  (let ((right (apply #'max 0 (mapcar (lambda (node) (+ (canvas-diagram-node-x node)
                                                        (canvas-diagram-node-w node)))
                                      nodes)))
        (reach (apply #'max 0 (mapcar (lambda (node) (canvas-sequence--self-reach model node ctx)) nodes))))
    (cons (max 0 (- reach right))
          (max 0 (- (canvas-sequence-height model) (canvas-sequence-top model))))))

(defun canvas-sequence--lay-out (diagram ctx)
  "Lay DIAGRAM out on CTX: a head box for each party, in a row, and the
lines of life below them; the nodes, in reading order."
  (let* ((model (canvas-diagram-model diagram))
         (measure (canvas-diagram-measure ctx))
         (nodes (mapcar (lambda (party) (canvas-sequence--head-node model party))
                        (canvas-sequence-parties model))))
    (dolist (node nodes)
      (canvas-diagram-size-node diagram node measure))
    (canvas-sequence--place-heads nodes)
    (setf (canvas-sequence-top model)
          (apply #'max 0 (mapcar #'canvas-diagram-node-h nodes)))
    (setf (canvas-diagram-slack diagram) (canvas-sequence--slack model nodes ctx))
    nodes))

;;;; The drawing

(defconst canvas-sequence--dash 6
  "The pixels of a dash of a line of life, and of the gap after it.")

(defun canvas-sequence--dashed-line (ctx x y0 y1)
  "Draw a dashed line down CTX at X from Y0 to Y1.  The module draws no
dashes of its own, so this draws them one by one."
  (cl-loop for y from y0 below y1 by (* 2 canvas-sequence--dash)
           do (canvas-cairo-move-to ctx x y)
              (canvas-cairo-line-to ctx x (min y1 (+ y canvas-sequence--dash))))
  (canvas-cairo-stroke ctx))

(defun canvas-sequence--draw-lifelines (diagram ctx)
  "Draw a line of life below each head box of DIAGRAM on CTX."
  (let ((model (canvas-diagram-model diagram)))
    (canvas-diagram-set-rgb ctx (canvas-diagram-color :edge))
    (canvas-cairo-set-line-width ctx 1)
    (dolist (node (canvas-diagram-nodes diagram))
      (canvas-sequence--dashed-line ctx (canvas-sequence--lifeline-x node)
                                    (canvas-sequence-top model)
                                    (canvas-sequence-height model)))))

(defun canvas-sequence--arrow-head (ctx x y direction)
  "Draw the head of an arrow at X and Y on CTX, DIRECTION being 1 for one
that points right and -1 for one that points left."
  (let ((back (* direction -8)))
    (canvas-cairo-move-to ctx x y)
    (canvas-cairo-line-to ctx (+ x back) (- y 4))
    (canvas-cairo-move-to ctx x y)
    (canvas-cairo-line-to ctx (+ x back) (+ y 4))
    (canvas-cairo-stroke ctx)))

(defun canvas-sequence--draw-line (ctx x0 x1 y dashed)
  "Draw the line of a message on CTX from X0 to X1 at Y, DASHED or whole."
  (if dashed
      (cl-loop with step = (if (> x1 x0) (* 2 canvas-sequence--dash) (- (* 2 canvas-sequence--dash)))
               for x = x0 then (+ x step)
               while (if (> x1 x0) (< x x1) (> x x1))
               do (canvas-cairo-move-to ctx x y)
                  (canvas-cairo-line-to ctx (if (> x1 x0)
                                                (min x1 (+ x canvas-sequence--dash))
                                              (max x1 (- x canvas-sequence--dash)))
                                        y)
               finally (canvas-cairo-stroke ctx))
    (canvas-cairo-move-to ctx x0 y)
    (canvas-cairo-line-to ctx x1 y)
    (canvas-cairo-stroke ctx)))

(defun canvas-sequence--draw-text (ctx text x y font)
  "Write TEXT on CTX centred on X, sitting above Y."
  (let ((size (canvas-cairo-text-size ctx text font)))
    (canvas-cairo-text ctx (- x (/ (car size) 2.0)) (- y (cdr size) 4) text font)))

(defun canvas-sequence--draw-self (diagram ctx message y font)
  "Draw MESSAGE of DIAGRAM at Y on CTX as a loop back to the line of life
it came from."
  (let* ((x (canvas-sequence--lifeline-x (canvas-sequence--node-of diagram (canvas-sequence-message-from message))))
         (out (+ x canvas-sequence--self-out)))
    (canvas-sequence--draw-line ctx x out y (canvas-sequence-message-dashed message))
    (canvas-cairo-move-to ctx out y)
    (canvas-cairo-line-to ctx out (+ y 12))
    (canvas-cairo-stroke ctx)
    (canvas-sequence--draw-line ctx out x (+ y 12) (canvas-sequence-message-dashed message))
    (canvas-sequence--arrow-head ctx x (+ y 12) -1)
    (canvas-sequence--draw-text ctx (canvas-sequence-message-text message) (+ out 8) y font)))

(defun canvas-sequence--draw-message (diagram ctx message y font)
  "Draw MESSAGE of DIAGRAM at Y on CTX: a line from one line of life to
another, its head at the party it goes to, and its text above it."
  (if (canvas-sequence-message-self-p message)
      (canvas-sequence--draw-self diagram ctx message y font)
    (let* ((x0 (canvas-sequence--lifeline-x (canvas-sequence--node-of diagram (canvas-sequence-message-from message))))
           (x1 (canvas-sequence--lifeline-x (canvas-sequence--node-of diagram (canvas-sequence-message-to message)))))
      (canvas-sequence--draw-line ctx x0 x1 y (canvas-sequence-message-dashed message))
      (canvas-sequence--arrow-head ctx x1 y (if (> x1 x0) 1 -1))
      (canvas-sequence--draw-text ctx (canvas-sequence-message-text message) (/ (+ x0 x1) 2.0) y font))))

(defun canvas-sequence--draw-edges (diagram ctx)
  "Draw the lines of life of DIAGRAM on CTX, and then its messages."
  (let ((model (canvas-diagram-model diagram))
        (font (canvas-diagram-font)))
    (canvas-sequence--draw-lifelines diagram ctx)
    (canvas-diagram-set-rgb ctx (canvas-diagram-color :edge))
    (canvas-cairo-set-line-width ctx 1.5)
    (cl-loop for message in (canvas-sequence-messages model)
             for i from 0
             do (canvas-sequence--draw-message diagram ctx message
                                               (canvas-sequence--message-y model i) font))))

;;;; The diagram: how the sequence plugs into canvas-diagram

(defconst canvas-sequence-callbacks
  (list :build (lambda (_diagram spec) (canvas-sequence-build spec))
        :layout #'canvas-sequence--lay-out
        :draw-edges #'canvas-sequence--draw-edges
        :node-key (lambda (_diagram node) (canvas-diagram-node-label node)))
  "How a sequence diagram plugs into canvas-diagram.")

(defun canvas-sequence-diagram (&optional callbacks)
  "A fresh diagram of a sequence, CALLBACKS, a plist, before its own."
  (canvas-diagram-create :callbacks (append callbacks canvas-sequence-callbacks)))


;;;; The mode, and showing a diagram

(define-derived-mode canvas-sequence-mode canvas-diagram-mode "Sequence"
  "Major mode of a buffer showing a sequence diagram on a canvas.

The keyboard is on one party.  The keys that move point move it, and
\[canvas-diagram-visit-source] goes to the place the party was read
from.  \[canvas-diagram-write] writes the picture as a PNG, an SVG or a
PDF.

\{canvas-sequence-mode-map}")

;;;###autoload
(defun canvas-sequence-show (spec &optional name)
  "Show SPEC, a sequence as `canvas-sequence-build' reads it, in the
buffer NAME, or *canvas-sequence*.  Return the buffer."
  (canvas-diagram-show (or name "*canvas-sequence*") #'canvas-sequence-mode
                       (canvas-sequence-diagram) spec))

;;;###autoload
(defun canvas-sequence-export (spec file)
  "Draw SPEC into FILE, a PNG, an SVG or a PDF by its name; FILE.
No buffer and no frame are needed, so this works in batch."
  (canvas-diagram-export (canvas-sequence-diagram) spec file))

(provide 'canvas-sequence)
;;; canvas-sequence.el ends here
