# canvas-sequence

canvas-sequence draws a sequence diagram on an Emacs 32 canvas: a box
for each party, a dashed line of life below it, and an arrow for each
message, one under the other in the order they happen.

It draws with the canvas-cairo module of
[canvas-diagram](https://github.com/Daskeladden/canvas-diagram) and
takes its fonts and colours from there. It needs no browser and no
node.

This is a prototype.

## The spec

A diagram is a list of lines:

```elisp
(canvas-sequence-show
 '((party "host" "Host")
   (party "toe" "TOE")
   (message "host" "toe" "open socket")
   (message "toe" "toe" "start timer")
   (message "toe" "host" "connected" :dashed t)))
```

A party is named once, and the order of those lines is the order of the
columns. `(party NAME)` alone calls the party by its name. A message
names the party it comes from, the party it goes to, and its text; both
parties must be named already, and a name that no party has is an error
that says so. A message to the party it came from loops back to the
same line of life. `:dashed t` draws the arrow as a dashed line, which
is how a reply is usually drawn. `:pos` on either line records where it
was read from, so that the picture can jump back to the source.

canvas-mermaid and canvas-plantuml are to read their own languages into
this spec, so that one drawing serves both.

## Commands

- `canvas-sequence-show` draws a spec in a buffer.
- `canvas-sequence-export` writes a spec to a PNG, an SVG or a PDF, and
  works in batch.

The buffer is a canvas-diagram buffer, so the keys that move point walk
the parties, `C-x C-w` writes the picture, and the menu on `SPC` changes
how it looks.

## Requirements

- Emacs 32.0.50, built from source, with canvas images and modules.
- canvas-diagram and its compiled `canvas-cairo` module, side by side
  with this repository.

## Build and test

```sh
make -C ../canvas-diagram   # the canvas-cairo module, once
make test
make compile
```
