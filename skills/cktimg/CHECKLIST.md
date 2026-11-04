# The book's look, item by item

Review a drawing against every item. An item is *ok*, or it carries a
**complaint** that names devices or nets. The rung beside each item is where
its complaint is usually fixed.

Every net one piece and no wire on another net's pin are cktImg's to keep;
a drawing that breaks one (a `gates` finding) is a cktImg bug, to report with the deck rather
than fix with hints.

| item | read it in | rung |
|---|---|---|
| Supply on top, ground at the bottom, current flowing down each column | `pos` y; the image | 0 |
| Each net plays its role: inputs and outputs are ports, supply and ground are symbols, a bias line is named | `labels`, the ports in the image | 0 |
| Matched devices (a differential pair, a current mirror, a cross-coupled pair) share a row | one `grid` row; `decisions` | 1 |
| A stack stands in one column in series order | one `grid` column, rows down the chain | 1 |
| A circuit with a left-right symmetry is drawn as its mirror image, what maps to itself on the axis | mates' `pos` x summing to one value | 1 |
| Signal enters on the left and leaves on the right (a differential output at both sides) | the ports' x | 0 |
| A net is a wire unless the book would name it (a bias line, a supply) | `labels` | 1 |
| Nothing crowded or sprawling; few crossings and bends | `metrics`; the image | style |
