# Turing Machine in Jai

This is an [Esoteric](https://en.wikipedia.org/wiki/Esoteric_programming_language) Programming Languages based on [Turing Machine](https://en.wikipedia.org/wiki/Turing_machine) and a simple [Declarative](https://en.wikipedia.org/wiki/Declarative_programming) [Metaprogramming](https://en.wikipedia.org/wiki/Metaprogramming) language that generates the rules of the Machine.

Check out [./examples/](./examples/) folder and have fun.

## Quick Start

```console
$ jai-linux ./turj.jai
$ ./turj ./examples/04-paren.turj
```

## Language

The Language consist of 3 sub-languages:
1. The Base Language - the language that describes the state transitions (rules) of the Turning Machine.
2. The Generative Language - a Declartive extension of the Base Language that enables us to generate the rules from sets of symbols.
3. The Command Language - basically a set of command to control the Machine. Start, debug, configure the tape, etc.

### The Base Language

Base language is a sequence of `Rules`:

```abnf
Rules          = *Rule
Rule           = State Read Write Arrow Next
State          = Symbol
Read           = Symbol
Write          = Symbol
Arrow          = '<-' / '->'
Next           = Symbol
Symbol         = UnquotedSymbol / QuotedSymbol
UnquotedSymbol = 1*(DIGIT / ALPHA / '_')
QuotedSymbol   = "'" <any character even "'" but with the conventional backslash escaping> "'"
```

Each `Rule` describes the following transition: Given that the current state is `State` and the symbol under the head is `Read` replace that symbol with `Write` move the head in the direction of `Arrow` and switch the current state to `Next`.

If the there is no `Rule` that describes the current `State` and `Read` of the machine it halts.

An example of a program that increments a binary numbers on the tape written in an LSB order using symbols `0` and `1`:

```rust
I 0 1 -> H
I 1 0 -> I
```

Actually executing this program is the responsibility of the Command Language.

### The Generative Language

### The Command Language
