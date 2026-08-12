# Control Flow

```ravi
score = 72
if score >= 90:
    mudrisu("excellent")
elif score >= 50:
    mudrisu("pass")
else:
    mudrisu("retry")
```

Loops use indentation:

```ravi
for value in [1, 2, 3]:
    if value == 2:
        continue
    mudrisu(value)
```

```ravi
count = 3
while count > 0:
    mudrisu(count)
    count = count - 1
```

`break` exits the nearest loop. `continue` advances to the next iteration. `range` and the Kanglish spelling `shreni` produce integer sequences for counted loops.
