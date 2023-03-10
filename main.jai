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
        print("ERROR: could not read %\n", file_path);
        exit(1);
    }
    lexer := lexer_from_string(content, file_path);

    rows: [..]Row;
    _, result := lexer_peek(*lexer);
    while result == .VALID {
        row, ok := parse_row(*lexer);
        if !ok then exit(1);
        array_add(*rows, row);
        _, result = lexer_peek(*lexer);
    }

    tape: [..]string;
    // TODO: customizable tape
    // array_add(*tape, "0", "0", "1", "0", "1", "0");
    // array_add(*tape, "@", "0", "1", "0", "1", "#", "1", "1", "0", "0");
    array_add(*tape, "(",  ")", "(", "(", ")", ")",  "#",  "0");
    assert(tape.count > 0);
    default: string = tape[tape.count - 1];
    head: int = 0;
    assert(rows.count > 0);
    state: string = rows[0].state.text;

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
}
