# The book's look, item by item

Review a drawing against every item. An item is *ok*, or it carries a
**complaint** that names devices or nets. The rung beside each item is where
its complaint is usually fixed.

| item | read it in | rung |
|---|---|---|
| Clean: `gates` is empty. A finding is a cktImg bug: report it with the deck | `gates` | none |
| No name lies on a symbol, another name or another net's wire. A finding is a cktImg bug: report it with the deck | `text_overlaps` | none |
| Each gate faces the net it is driven from, as the book draws it | the image; `decisions` (`face`) | 2 |
| Supply on top, ground at the bottom, current flowing down each column | `grid`; the image | 0, then 2 |
| Each net plays its role: inputs and outputs are ports, supply and ground are symbols, a bias line is named or carries a port at each gate | `metrics.labelled`, `metrics.ported`, the ports in the image | 0 |
| Matched devices (a differential pair, a current mirror, a cross-coupled pair) share a row | one `grid` row; `decisions` | 1, then 2 |
| A stack stands in one column in series order | one `grid` column, rows down the chain | 1, then 2 |
| Repeated cells (a bit slice, a stage per channel) are drawn alike, side by side on one level | the `grid` rows of each cell's devices | 2 (`stage`, `repeat`) |
| A circuit with a left-right symmetry is drawn as its mirror image, what maps to itself on the axis | mates' `pos` x summing to one value | 1 |
| Signal enters on the left and leaves on the right (a differential output at both sides) | the ports' x | 0, then 2 |
| A net is a wire unless the book would name it (a bias line, a supply) | `metrics.labelled` | 2 |
| A named net carries one name a wired piece, beside its wire and never along it | the image; `text_overlaps` | 2 (`wire <net> at`) |
| Nothing crowded or sprawling; few crossings and bends | `metrics`; the image | style |
