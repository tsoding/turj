#import "Basic";
#import "String";
#import "File";
#load "lexer.jai";

// TODO: compound symbols

Rule :: struct {
    state: Token;
    read: Token;
    write: Token;
    step: Token;
    next: Token;
}

Set :: struct {
    name: Token;
    items: [..]Token;
}

Top_Level :: struct {
    rules: [..]Rule;
    sets: [..]Set;
    runs: [..]Run;
}

Run :: struct {
    state: Token;
    tape: [..]Token;
    default: Token;
    loc: Loc;
}

parse_top_level :: (using top_level: *Top_Level, lexer: *Lexer) -> ok: bool {
    first: Token;
    if !lexer_expect_token(lexer, *first, .SYMBOL, .COMMAND) return false;
    if first.kind == {
        case .COMMAND; {
            if first.text == "#run" {
                run: Run;
                run.loc = first.loc;

                if !lexer_expect_token(lexer, *first, .SYMBOL) return false;

                run.state = first;

                if !lexer_expect_token(lexer, *first, .OBRACKET) return false;

                while lexer_peek(lexer, *first) == .VALID && first.kind == .SYMBOL {
                    lexer_next(lexer, *first);
                    array_add(*run.tape, first);
                }
                if !lexer_expect_token(lexer, *first, .CBRACKET) return false;

                if run.tape.count == 0 {
                    print("%:%:%: ERROR: tape may not be empty, because we are using the last symbol as the symbol the entire infinite tape is initialized with.\n", first.loc.file_path, first.loc.row, first.loc.col);
                    return false;
                }
                run.default = run.tape[run.tape.count - 1];

                array_add(*runs, run);

                return true;
            } else {
                print("%:%:%: ERROR: unknown command %\n", first.loc.file_path, first.loc.row, first.loc.col, first.text);
                return false;
            }
        }

        case .SYMBOL; {
            read_or_equal: Token;
            if !lexer_expect_token(lexer, *read_or_equal, .SYMBOL, .EQUALS) return false;

            if read_or_equal.kind == {
                case .SYMBOL; {
                    rule: Rule;
                    rule.state = first;
                    rule.read = read_or_equal;
                    if !lexer_expect_token(lexer, *rule.write, .SYMBOL) return false;
                    if !lexer_expect_token(lexer, *rule.step, .ARROW)   return false;
                    if !lexer_expect_token(lexer, *rule.next, .SYMBOL)  return false;

                    for_token: Token;
                    if lexer_peek(lexer, *for_token) == .VALID && for_token.kind == .FOR {
                        lexer_next(lexer, *for_token);

                        symbol: Token;
                        if !lexer_expect_token(lexer, *symbol, .SYMBOL) return false;

                        colon: Token;
                        if !lexer_expect_token(lexer, *colon, .COLON) return false;

                        // TODO: introduce the notion of Set expressions and parse the Set expression next in here
                        set: Token;
                        if !lexer_expect_token(lexer, *set, .SYMBOL) return false;

                        // TODO: defer the expansion of `for` so we can define sets anywhere
                        for sets {
                            if it.name.text == set.text {
                                for it.items {
                                    rule_from_template :: (template: Rule, symbol: Token, replace: Token) -> Rule {
                                        using instance := template;
                                        if state.text == symbol.text then state = replace;
                                        if read.text == symbol.text then read = replace;
                                        if write.text == symbol.text then write = replace;
                                        // TODO: step should be also treated as replacible symbol in the templates
                                        //if step.text == symbol.text then step = replace;
                                        if next.text == symbol.text then next = replace;
                                        return instance;
                                    }

                                    array_add(*rules, rule_from_template(rule, symbol, it));
                                }
                                return true;
                            }
                        }

                        // TODO: nested for-s

                        print("%:%:%: ERROR: set % does not exist\n", set.loc.file_path, set.loc.row, set.loc.col, set.text);
                        return false;
                    } else {
                        array_add(*rules, rule);
                        return true;
                    }
                }
                case .EQUALS; {
                    set: Set;
                    set.name = first;

                    ignore: Token;
                    if !lexer_expect_token(lexer, *ignore, .OCURLY) return false;

                    next: Token;
                    while lexer_peek(lexer, *next) == .VALID && next.kind == .SYMBOL {
                        lexer_next(lexer, *next);
                        // TODO: check if the symbols are unique
                        array_add(*set.items, next);
                    }
                    if !lexer_expect_token(lexer, *next, .CCURLY) return false;

                    array_add(*sets, set);

                    return true;
                }
                case; {
                    assert(false, "unreachable");
                    return false;
                }
            }
        }

        case; {
            assert(false, "unreachable");
            return false;
        }
    }
}

lexer_expect_token :: (using lexer: *Lexer, token: *Token, kinds: .. Token_Kind) -> bool {
    result := lexer_next(lexer, token);
    if #complete result == {
        case .VALID; {
            for kinds {
                if token.kind == it {
                    return true;
                }
            }

            sb: String_Builder;
            for kinds {
                if it_index > 0 then print_to_builder(*sb, " or ");
                print_to_builder(*sb, "%", it);
            }

            print("%:%:%: ERROR: expected % but got %\n",
                  token.loc.file_path, token.loc.row, token.loc.col,
                  // TODO: free the string from String_Builder
                  builder_to_string(*sb),
                  token.kind);
            return false;
        }
        case .END; #through;
        case .UNCLOSED_STRING; #through;
        case .UNKNOWN; {
            sb: String_Builder;
            for kinds {
                if it_index > 0 then print_to_builder(*sb, " or");
                print_to_builder(*sb, "%", it);
            }

            // TODO: free the string from String_Builder
            print("%:%:%: ERROR: expected % but got %\n", token.loc.file_path, token.loc.row, token.loc.col, builder_to_string(*sb), result);
            return false;
        }
    }
}

execute_run :: (using run: *Run, rules: []Rule) {
    print("%:%:%: #run\n", loc.file_path, loc.row, loc.col);

    head: int = 0;

    while loop := true {
        while head >= tape.count {
            array_add(*tape, default);
        }

        sb : String_Builder;
        print_to_builder(*sb, "%:", state);
        head_start := 0;
        head_end := 0;
        for tape {
            if it_index == head then head_start = builder_string_length(*sb) + 1;
            print_to_builder(*sb, " %", it);
            if it_index == head then head_end = builder_string_length(*sb);
        }
        // TODO: free the string from String_Builder
        print("%\n", builder_to_string(*sb));
        for 0..head_start-1 print(" ");
        for head_start..head_end-1 print("^");
        print("\n");

        for *rules {
            if it.state.text == state.text && it.read.text == tape[head].text {
                tape[head] = it.write;
                state      = it.next;
                if it.step.text == {
                    case "<-"; head -= 1;
                    case "->"; head += 1;
                    case; assert(false, "unreachable");
                }
                if head < 0 break loop;
                continue loop;
            }
        }
        break loop;
    }

    print("-- HALT --\n");
}

main :: () {
    args := get_command_line_arguments();

    if args.count < 2 {
        print("Usage: % <input.turj>\n", args[0]);
        print("ERROR: no input was provided\n");
        exit(1);
    }

    file_path := args[1];
    content, ok := read_entire_file(file_path);
    if !ok {
        print("ERROR: could not read file %\n", file_path);
        exit(1);
    }
    lexer := lexer_from_string(content, file_path);

    top_level: Top_Level;
    runs: [..]Run;
    first: Token;
    while lexer_peek(*lexer, *first) == .VALID {
        if !parse_top_level(*top_level, *lexer) then exit(1);
    }

    for *top_level.runs {
        execute_run(it, top_level.rules);
    }
}
