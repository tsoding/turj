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
1. The Base Language — the language that describes the state transitions (rules) of the Turning Machine.
2. The Generative Language — a Declartive extension of the Base Language that enables us to generate the rules from sets of symbols.
3. The Command Language — basically a set of command to control the Machine. Start, debug, configure the tape, etc.

### The Base Language

Base Language is a sequence of `Rules`. Here is its [ABNF](https://en.wikipedia.org/wiki/Augmented_Backus%E2%80%93Naur_form):

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

If there is no `Rule` that describes the current `State` and `Read` of the machine it halts.

An example of a program that increments a binary numbers on the tape written in an [LSB](https://en.wikipedia.org/wiki/Bit_numbering) order using symbols `0` and `1`:

```rust
I 0 1 -> H
I 1 0 -> I
```

Actually executing this program is the responsibility of the Command Language.

### The Generative Language

As of right now Generative Language consist of [set definitions](https://en.wikipedia.org/wiki/Set_theory) and [universal quantifications](https://en.wikipedia.org/wiki/Universal_quantification) (Don't get scared! These concepts are relatively easy to understand intuitively by looking at some examples).

### Defining Sets

The syntax of the Set Definition:

```abnf
SetDefinition = Name '=' '{' *Symbol '}'
Name          = Symbol
```

Here is how it usually looks like:

```rust
Bit = {0 1}
Fruits = {Apple Banana Cherry}
```

Set is just a collection of unique symbols (they can't repeat).

### Universal Quantifier

This construction extends the definition of the `Rule` in the following way:

```abnf
Rule = State Read Write Arrow Next ["for" Var ":" Set]
Var  = Symbol
Set  = Symbol
```

This basically generates `N` rules where `N` is the size of `Set` for each element of `Set`. For example this code

```rust
Fruits = {Apple Banana Cherry}
Eat fruit Eaten -> Eat for fruit: Fruits
```

expands into

```rust
Eat Apple  Eaten -> Eat
Eat Banana Eaten -> Eat
Eat Cherry Eaten -> Eat
```

Which is basically a program that goes through the entire infinite tape of `Fruits` and eats all of them.

### The Command Language

Right the Command Language has only `#run` command. But I plan to add some stuff for debugging as well.

#### Running the program

```abnf
RunCommand = "#run" Entry Tape
Entry      = Symbol
Tape       = "[" *(Symbol) "]"
```

`Entry` is the initial state of the machine. `Tape` is the initial state of the tape. Let's take the the fruit eating program and run it:

```rust
Fruits = {Apple Banana Cherry}
Eat fruit Eaten -> Eat for fruit: Fruits
#run Eat [Apple Banna Cherry Cherry Apple Banana]
```

You may have as many `#run` commands in a single file as you want. They are going to be executed in the order of their definition.

The tape is actually infinite to the right (not to the left though). `Tape` defines only the first symbols. The rest of the infinite tape is initialized with the last `Symbol` of `Tape`. Thus `Tape` may not be empty (the Interpreter will tell you that anyway, so don't worry). If you "underflow" the tape to the left the Machine halts.
