# The book's look, item by item

Review a drawing against every item. An item is *ok*, or it carries a
**complaint** that names devices or nets. The rung beside each item is where
its complaint is usually fixed; start there, descend only when that rung
cannot express the fix.

The report's `gates` are the engine's to keep (every net one piece, no wire
on another net's point, no wire through a symbol, no symbol on another); a
failing gate is an engine bug to report with the deck, never a complaint to
fix with hints.

| item | read it in | rung |
|---|---|---|
| Each net plays the role it has in the circuit (supply, ground, input, output, bias, signal) | `decisions` (`role`) | 1 |
| Matched devices are recognized as their group: differential pair, current mirror, cross-coupled pair, stack | `decisions` (`group`) | 1 |
| A circuit with a left-right symmetry is drawn as its mirror image; what maps to itself sits on the axis | `decisions` (`symmetric`, `axis`), `metrics.symmetry` | 1 |
| Supply on top, ground at the bottom, current flowing down each column | `metrics.flow`, `grid` | 2 |
| Matched devices share a row; a stack stands in one column in series order | `grid`, `metrics.alignment` | 2 |
| Signal enters on the left and leaves on the right (a differential output at both sides) | `grid`, `metrics.flow` | 2 |
| Each gate faces the net it is driven from | `decisions` (`face`) | 2 |
| A net is a wire unless the book would name it (a bias line, a supply); no stray labels | `metrics.labels`, `requests` | 2 |
| Few crossings, few bends, no long detours | `metrics.crossings`, `metrics.bends`, `metrics.detour` | 2, then 3 |
| Nothing crowded: names and wires keep clear of symbols and each other | `metrics.clearance` | 3, then 4 |
| Any one placement or route the user asked for exactly | the image | 3 to 5 |
