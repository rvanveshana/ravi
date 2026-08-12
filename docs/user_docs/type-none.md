# None (`none`)

`none` represents the absence of a value. It is useful for optional results and procedures that do not return meaningful data.

```ravi
result = none

kriya log_message(message):
    mudrisu(message)
    kodu none
```

`none` is falsey in a condition:

```ravi
value = none
if not value:
    mudrisu("no value")
```

Compare it with equality or identity when testing for absence:

```ravi
if value is none:
    mudrisu("missing")
```

`none` has no methods.
