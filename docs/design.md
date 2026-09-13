# canvas-sequence: design

## What it draws

A sequence diagram answers who says what to whom, and in which order.
The parties stand in a row of boxes at the top. Below each box runs a
dashed line of life. Each message is a row: an arrow from one line of
life to another, with its text above it. A message a party sends itself
loops out to the right and back.

The rows are evenly spaced, so the picture reads as time going down.

## The model

`canvas-sequence-build` reads a spec into three structures:

- `canvas-sequence-party`: its name, the label its box shows, and where
  it was read from.
- `canvas-sequence-message`: the party it comes from, the party it goes
  to, its text, whether it is dashed, and where it was read from.
- `canvas-sequence`: the parties in order, the messages in order, and
  the top, the y at which the lines of life start, which the layout
  sets.

A message that names a party no line has named is a user error. The
model is built before anything is drawn, so a bad spec never reaches
the canvas.

## The layout

The head boxes take the size their text needs, and stand in a row with
a gap between them. The line of life of a party runs down the middle of
its box. Message `i` sits at `top + head-gap + i * row`.

The drawing goes below and beside the boxes, so the layout tells
canvas-diagram how much room it takes beyond them, through the `slack`
of the diagram: the height of the messages, and the reach of the widest
loop a party sends itself.

## What is not built yet

- Activations, the bars that show a party at work.
- Blocks: loop, alt, opt and par, with their frames and labels.
- Notes over a party or between two.
- A message as a node of its own, so that the keyboard can walk the
  messages and jump to the line each came from.
- Readers: canvas-mermaid for `sequenceDiagram` and canvas-plantuml for
  its sequence syntax, each reading into this spec.

## House rules

Tests first, with GIVEN, WHEN and THEN comments. Short functions. DRY.
Offensive programming. No stubs in production code. Run `make test` and
`make compile` after every edit; the compile treats a warning as an
error.
