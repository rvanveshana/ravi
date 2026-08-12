# Kannada and Kanglish Examples

Kanglish lets Kannada speakers write Kannada keywords with Latin characters.
The runnable examples below use the current Kanglish profile. Kannada script is
shown in comments and strings as a language reference.

```ravi
kriya namaskara hesaru:
    mudrisu("Namaskara " + hesaru)

prati hesaru alli ["Ravi", "Asha"]:
    namaskara(hesaru)
```

A Kannada-script illustration of the same idea:

```text
ಕ್ರಿಯೆ ನಮಸ್ಕಾರ ಹೆಸರು:
    ಮುದ್ರಿಸು("ನಮಸ್ಕಾರ " + ಹೆಸರು)
```

A Kannada/Kanglish variadic function:

```ravi
kriya serisu(modala, *mikkidavu, **aaykegalu):
    phala = modala + mikkidavu[0]
    kodu phala + aaykegalu["bonus"]

mudrisu(serisu(1, 2, bonus = 4))
```

The canonical executable fixtures in `examples/` use spellings accepted by the current lexer and are the best source for runnable profile examples.
