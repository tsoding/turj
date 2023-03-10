#import "Basic";
#import "String";
#import "File";
#load "lexer.jai";

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

parse_row :: (lexer: *Lexer) -> row: Row, ok: bool {
    row: Row;
    ok: bool;
    row.state,  ok = lexer_expect_token(lexer, .SYMBOL); if !ok return row, false;
    row.read,   ok = lexer_expect_token(lexer, .SYMBOL); if !ok return row, false;
    row.write,  ok = lexer_expect_token(lexer, .SYMBOL); if !ok return row, false;
    row.step,   ok = lexer_expect_token(lexer, .ARROW);  if !ok return row, false;
    row.switch, ok = lexer_expect_token(lexer, .SYMBOL); if !ok return row, false;
    return row, true;
}

parse_command :: (lexer: *Lexer, rows: []Row) -> bool {
    token, ok := lexer_expect_token(lexer, .COMMAND);
    if !ok return false;
    if token.text == "#run" {
        print("%:%:%: #run\n", token.loc.file_path, token.loc.row, token.loc.col);

        token, ok = lexer_expect_token(lexer, .SYMBOL);
        if !ok return false;

        state := token.text;

        tape: [..]string;
        token, ok = lexer_expect_token(lexer, .OBRACKET);
        if !ok return false;

        result: Lexer_Result;
        token, result = lexer_next(lexer);
        while result == .VALID && token.kind != .CBRACKET {
            array_add(*tape, token.text);
            token, result = lexer_next(lexer);
        }

        if result != .VALID {
            print("%:%:%: ERROR: expected % but got %\n", token.loc.file_path, token.loc.row, token.loc.col, Token_Kind.CBRACKET, result);
            return false;
        } else if token.kind != .CBRACKET {
            print("%:%:%: ERROR: expected % but got %\n", token.loc.file_path, token.loc.row, token.loc.col, Token_Kind.CBRACKET, token.kind);
        }

        if tape.count == 0 {
            print("%:%:%: ERROR: tape may not be empty, because we are using the last symbol as the symbol the entire infinite tape is initialized with.\n", token.loc.file_path, token.loc.row, token.loc.col);
        }
        default: string = tape[tape.count - 1];

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

        return true;
    } else {
        print("%:%:%: ERROR: unknown command %\n", token.loc.file_path, token.loc.row, token.loc.col, token.text);
        return false;
    }
}

lexer_expect_token :: (using lexer: *Lexer, kind: Token_Kind) -> token: Token, ok: bool {
    token, result := lexer_next(lexer);
    if #complete result == {
        case .VALID; if token.kind == kind {
            return token, true;
        } else {
            print("%:%:%: ERROR: expected % but got %\n", token.loc.file_path, token.loc.row, token.loc.col, kind, token.kind);
            return token, false;
        }
        case .END; #through;
        case .UNCLOSED_STRING; #through;
        case .UNKNOWN; {
            print("%:%:%: ERROR: expected % but got %\n", token.loc.file_path, token.loc.row, token.loc.col, kind, result);
            return token, false;
        }
    }
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

    rows: [..]Row;
    first, result := lexer_peek(*lexer);
    while result == .VALID {
        if first.kind == .COMMAND {
            if !parse_command(*lexer, rows) then exit(1);
        } else {
            row, ok := parse_row(*lexer);
            if !ok then exit(1);
            array_add(*rows, row);
        }
        first, result = lexer_peek(*lexer);
    }
}
