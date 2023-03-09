#import "Basic";
#import "String";
#import "File";

Step :: enum int {
    LEFT :: -1;
    RIGHT :: 1;
}

Row :: struct {
    state: string;
    read: string;
    write: string;
    step: Step;
    switch: string;
}

parse_step :: (source: *string) -> step: Step, ok: bool {
    step, ok := parse_token(source); if !ok return .LEFT, ok;
    if step == {
    case "<-"; return .LEFT,  true;
    case "->"; return .RIGHT, true;
    }
    return .LEFT, false;
}

parse_row :: (source: *string) -> row: Row, ok: bool {
    row: Row;
    ok: bool; 
    step: string;
    row.state,  ok = parse_token(source); if !ok return row, false;
    row.read,   ok = parse_token(source); if !ok return row, false;
    row.write,  ok = parse_token(source); if !ok return row, false;
    row.step,   ok = parse_step(source);  if !ok return row, false;
    row.switch, ok = parse_token(source); if !ok return row, false;
    return row, true;
}

main :: () {
    // TODO: accept file path through the arguments
    file_path :: "paren.turj";
    content, ok := read_entire_file(file_path);
    if !ok {
        print("ERROR: could not read %\n", file_path);
    }

    rows: [..]Row;
    for *split(content, "\n") {
        row, ok := parse_row(it);
        if ok then array_add(*rows, row);
    }

    print("%\n", rows);

    tape: [..]string;
    /* array_add(*tape, "0", "0", "1", "0", "1", "0"); */
    /* array_add(*tape, "@", "0", "1", "0", "1", "#", "1", "1", "0", "0"); */
    array_add(*tape, "(",  ")", "(", "(", ")", ")",  "#",  "0");
    assert(tape.count > 0);
    default: string = tape[tape.count - 1];
    head: int = 0;
    assert(rows.count > 0);
    state: string = rows[0].state;

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
            if it.state == state && it.read == tape[head] {
                tape[head] = it.write;
                state      = it.switch;
                head      += cast(int) it.step;
                if head < 0 break loop;
                continue loop;
            }
        }
        break loop;
    }
}
