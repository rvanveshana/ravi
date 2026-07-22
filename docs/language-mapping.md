# Ravi language mapping

Ravi source files use Kannada/Kanglish by default. English is selected with
`# ravi: language=en` on the first line. A file must use one profile only;
language-neutral punctuation and collection literals are shared.
Keyword spellings are contextual: after `.`, a name is always a member
identifier. Therefore `tago` is import at statement position and dictionary
lookup in `scores.tago(1)`.

## Currently implemented

| Meaning | Kannada (default) | English | Status |
|---|---|---|---|
| print | `mudrisu(x)` | `print(x)` | executable |
| function | `kriya` | `function` | executable |
| return | `kodu` | `return` | executable |
| if / else | `adre` / `illa` | `if` / `else` | executable |
| while | `vargu` | `while` | executable |
| for | `prati` | `for` | executable |
| in | `alli` | `in` | executable |
| break / continue | `nillu` / `munde` | `break` / `continue` | executable |
| range | `shreni` | `range` | executable |
| and / or / not | `mattu` / `athva` / `alla` | `and` / `or` / `not` | executable |
| append | `serisu(x)` | `append(x)` | executable |
| insert | `haku(position, value)` | `insert(position, value)` | executable |
| remove | `tegi(x)` | `remove(x)` | executable |
| pop | `kithu()` | `pop()` | executable |
| count | `enisu()` | `count()` | executable |
| sort | `jodisu()` | `sort()` | executable |
| reverse | `ultha()` | `reverse()` | executable |
| dictionary get | `tago(key)` | `get(key)` | executable |
| dictionary update | `badala(key, value)` | `update(key, value)` | executable |
| dictionary remove | `tegi(key)` | `pop(key)` | executable |
| dictionary keys / values / items | `kili()` / `bele()` / `jodi()` | `keys()` / `values()` / `items()` | executable |
| set union / intersection / difference | `koodu()` / `ondu()` / `bere()` | `union()` / `intersection()` / `difference()` | executable |
| contains | `olagide(x)` | `contains(x)` | executable |
| clear | `khaali()` | `clear()` | executable |
| string/collection length | `gatra()` | `length()` | executable |
| string lower/upper/strip | `chikku()` / `doddu()` / `kadi()` | `lower()` / `upper()` / `strip()` | executable |
| runtime type query | `vidha(x)` | `type(x)` | executable |

Collection literals are profile-neutral:

```text
[1, 2, 3]       list/array
(1, 2, 3)       tuple
{1, 2, 3}       set
{"a": 1}       dictionary
```

## Approved vocabulary for upcoming APIs

These spellings are the current design reference. Collection views and set
algebra are executable; the remaining entries are reserved for the standard
library.

| Python/API meaning | Ravi Kannada | Planned use |
|---|---|---|
| list insert | `haku` | list method |
| list remove | `tegi` | list/set/dict removal |
| list pop | `kithu` | remove and return |
| list clear | `khali` | canonical spelling under review; current code uses `khaali` |
| list index | `jaaga` | position lookup |
| list count | `enisu` | frequency |
| list sort | `jodisu` | ordering |
| list reverse | `ultha` | reverse |
| dictionary keys | `kili` | key view |
| dictionary values | `bele` | value view |
| dictionary items | `jodi` | key-value pairs |
| dictionary get | `tago` | safe lookup |
| dictionary update | `badala` | merge/update |
| length | `gatra` | common builtin |
| type | `vidha` | type query |
| sum | `motta` | aggregate |
| range | `saalu` | alternative under review; current code uses `shreni` |
| set union | `koodu` | combine |
| set intersection | `ondu` | common values |
| set difference | `bere` | values only in one set |

## Other reserved design vocabulary

The following mappings are recorded for future standard-library work:

| Area | Kannada/Kanglish mappings |
|---|---|
| strings | `ode` split, `jote` join, `badla` replace, `chikku` lower, `doddu` upper, `kadi` strip, `shuru` starts-with, `kone` ends-with, `huduk` find |
| files | `tere` open, `muchu` close, `odu` read, `bari` write, `salodu` readline, `hogu` seek |
| classes | `roopa` class, `tanna` self, `huttu` constructor, `guru` super, `vastu` object |
| errors | `nodu` try, `tappu` except, `kone` finally, `yese` raise, `khatri` assert |
| iteration | `taru` yield, `munde` next, `suttu` iterator, `srushti` generator |
| functional | `hachchu` map, `sosu` filter, `jote` zip, `ella` all, `gurutu` identity |

When a proposed spelling conflicts with an existing keyword or builtin, the
canonical table in `config/constants.zig` and this document must be updated
together. `mudrisu` remains the current Kannada print spelling; `torisu` is
not part of the active vocabulary.

Ravi intentionally does not include method or function overloading. Functions
use one signature with positional or keyword arguments; trailing numeric
defaults are supported. Keyword names are normalized to the declared
parameter order, and duplicate, unknown, or missing required arguments fail.
Variadic parameters use profile-neutral `*values` and `**options`; extra
positional arguments become a tuple and extra keyword arguments become a
dictionary. Fixed-arity calls retain the fast call path.
