#import "Basic";
#import "String";
#import "File";
#load "lexer.jai";

// TODO: compound symbols

Step :: enum int {
    LEFT :: -1;
    RIGHT :: 1;
}

Row :: struct {
    state: Token;
    read: Token;
    write: Token;
    step: Token;
    switch: Token;
}

parse_step :: (source: *string) -> step: Step, ok: bool {
    step, ok := parse_token(source); if !ok return .LEFT, ok;
    if step == {
    case "<-"; return .LEFT,  true;
    case "->"; return .RIGHT, true;
    }
    return .LEFT, false;
}

Set :: struct {
    name: Token;
    items: [..]Token;
}

Top_Level :: struct {
    rows: [..]Row;
    sets: [..]Set;
    runs: [..]Run;
}

parse_top_level :: (using top_level: *Top_Level, lexer: *Lexer) -> ok: bool {
    ok: bool;
    result: Lexer_Result;

    first: Token;
    first, ok = lexer_expect_token(lexer, .SYMBOL, .COMMAND);
    if !ok return false;

    if first.kind == {
        case .COMMAND; {
            if first.text == "#run" {
                run: Run;
                run.loc = first.loc;

                first, ok = lexer_expect_token(lexer, .SYMBOL);
                if !ok return false;

                run.state = first.text;

                first, ok = lexer_expect_token(lexer, .OBRACKET);
                if !ok return false;

                result: Lexer_Result;
                first, result = lexer_next(lexer);
                while result == .VALID && first.kind != .CBRACKET {
                    array_add(*run.tape, first.text);
                    first, result = lexer_next(lexer);
                }

                if result != .VALID {
                    print("%:%:%: ERROR: expected % but got %\n", first.loc.file_path, first.loc.row, first.loc.col, Token_Kind.CBRACKET, result);
                    return false;
                } else if first.kind != .CBRACKET {
                    print("%:%:%: ERROR: expected % but got %\n", first.loc.file_path, first.loc.row, first.loc.col, Token_Kind.CBRACKET, first.kind);
                    return false;
                }

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
            read_or_equal, ok = lexer_expect_token(lexer, .SYMBOL, .EQUALS);
            if !ok return false;

            if read_or_equal.kind == {
                case .SYMBOL; {
                    row: Row;
                    row.state = first;
                    row.read = read_or_equal;
                    row.write, ok = lexer_expect_token(lexer, .SYMBOL);
                    if !ok return false;
                    row.step, ok = lexer_expect_token(lexer, .ARROW);
                    if !ok return false;
                    row.switch, ok = lexer_expect_token(lexer, .SYMBOL);
                    if !ok return false;

                    for_token: Token;
                    for_token, result = lexer_peek(lexer);
                    if for_token.kind == .FOR {
                        // Parens
                        lexer_next(lexer);

                        symbol: Token;
                        symbol, ok = lexer_expect_token(lexer, .SYMBOL);
                        if !ok return false;

                        colon: Token;
                        colon, ok = lexer_expect_token(lexer, .COLON);
                        if !ok return false;

                        // TODO: introduce the notion of Set expressions and parse the Set expression next in here
                        set: Token;
                        set, ok = lexer_expect_token(lexer, .SYMBOL);
                        if !ok return false;

                        // TODO: defer the expansion of `for` so we can define sets anywhere
                        for sets {
                            if it.name.text == set.text {
                                for it.items {
                                    row_from_template :: (template: Row, symbol: Token, replace: Token) -> Row {
                                        using instance := template;
                                        if state.text == symbol.text then state = replace;
                                        if read.text == symbol.text then read = replace;
                                        if write.text == symbol.text then write = replace;
                                        // TODO: step should be also treated as replacible symbol in the templates
                                        //if step.text == symbol.text then step = replace;
                                        if switch.text == symbol.text then switch = replace;
                                        return instance;
                                    }

                                    array_add(*rows, row_from_template(row, symbol, it));
                                }
                                return true;
                            }
                        }

                        // TODO: nested for-s

                        print("%:%:%: ERROR: set % does not exist\n", set.loc.file_path, set.loc.row, set.loc.col, set.text);
                        return false;
                    } else {
                        array_add(*rows, row);
                        return true;
                    }
                }
                case .EQUALS; {
                    set: Set;
                    set.name = first;

                    ignore, next: Token;
                    ignore, ok = lexer_expect_token(lexer, .OCURLY);
                    if !ok return false;

                    next, result = lexer_next(lexer);
                    while result == .VALID && next.kind == .SYMBOL {
                        // TODO: check if the symbols are unique
                        array_add(*set.items, next);
                        next, result = lexer_next(lexer);
                    }

                    if result != .VALID {
                        print("%:%:%: ERROR: expected % but got %\n", next.loc.file_path, next.loc.row, next.loc.col, Token_Kind.CCURLY, result);
                        return false;
                    }

                    if next.kind != .CCURLY {
                        print("%:%:%: ERROR: expected % but got %\n", next.loc.file_path, next.loc.row, next.loc.col, Token_Kind.CCURLY, next.kind);
                        return false;
                    }

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

lexer_expect_token :: (using lexer: *Lexer, kinds: .. Token_Kind) -> token: Token, ok: bool {
    token, result := lexer_next(lexer);
    if #complete result == {
        case .VALID; {
            for kinds {
                if token.kind == it {
                    return token, true;
                }
            }

            sb: String_Builder;
            for kinds {
                if it_index > 0 then print_to_builder(*sb, " or ");
                print_to_builder(*sb, "%", it);
            }

            print("%:%:%: ERROR: expected % but got %\n",
                  token.loc.file_path, token.loc.row, token.loc.col,
                  builder_to_string(*sb),
                  token.kind);
            return token, false;
        }
        case .END; #through;
        case .UNCLOSED_STRING; #through;
        case .UNKNOWN; {
            sb: String_Builder;
            for kinds {
                if it_index > 0 then print_to_builder(*sb, " or");
                print_to_builder(*sb, "%", it);
            }

            print("%:%:%: ERROR: expected % but got %\n", token.loc.file_path, token.loc.row, token.loc.col, builder_to_string(*sb), result);
            return token, false;
        }
    }
}

Run :: struct {
    state: string;
    tape: [..]string;
    default: string;
    loc: Loc;
}

execute_run :: (using run: *Run, rows: []Row) {
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
        print("%\n", builder_to_string(*sb));
        for 0..head_start-1 print(" ");
        for head_start..head_end-1 print("^");
        print("\n");

        for *rows {
            if it.state.text == state && it.read.text == tape[head] {
                tape[head] = it.write.text;
                state      = it.switch.text;
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
        print("ERROR: no input was provided");
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
    first, result := lexer_peek(*lexer);
    while result == .VALID {
        ok := parse_top_level(*top_level, *lexer);
        if !ok then exit(1);
        first, result = lexer_peek(*lexer);
    }

    for *top_level.runs {
        execute_run(it, top_level.rows);
    }
}
