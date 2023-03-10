Loc :: struct {
    file_path: string;
    row: int;
    col: int;
}

Token_Kind :: enum {
    SYMBOL;
    COMMAND;
    ARROW;
    OBRACKET;
    CBRACKET;
    EQUALS;
    OCURLY;
    CCURLY;
    FOR;
    COLON;
}

Token :: struct {
    kind: Token_Kind;
    loc: Loc;
    text: string;
}

Lexer :: struct {
    // TODO: lexer does not handle Unicode
    content: string;
    file_path: string;
    cur, bol, row: int;
    peek_token: Token;
    peek_result: Lexer_Result;
    peek_full: bool;
}

lexer_skip_char :: (using lexer: *Lexer, n := 1) {
    assert(cur < content.count);
    for 1..n {
        x := content[cur];
        cur += 1;
        if x == #char "\n" {
            bol = cur;
            row += 1;
        }
    }
}

lexer_from_string :: (content: string, file_path := "") -> Lexer {
    return Lexer.{
        file_path = file_path,
        content = content,
    };
}

lexer_starts_with :: (using lexer: *Lexer, prefix: string) -> bool {
    return starts_with(slice(content, cur, content.count - cur), prefix);
}

lexer_trim_left :: (using lexer: *Lexer) {
    while cur < content.count && is_space(content[cur]) {
        lexer_skip_char(lexer);
    }
}

lexer_skip_line :: (using lexer: *Lexer) {
    while cur < content.count && content[cur] != #char "\n" {
        lexer_skip_char(lexer);
    }
    if cur < content.count then lexer_skip_char(lexer);
}

lexer_loc :: (using lexer: *Lexer) -> Loc {
    return Loc.{
        file_path = file_path,
        row = row + 1,
        col = cur - bol + 1,
    };
}

Lexer_Result :: enum {
    VALID;
    END;
    UNCLOSED_STRING;
    UNKNOWN;
}

LITERAL_TOKENS : []struct { prefix: string; kind: Token_Kind; } = .[
    .{"<-", .ARROW},
    .{"->", .ARROW},
    .{"[", .OBRACKET},
    .{"]", .CBRACKET},
    .{"=", .EQUALS},
    .{"{", .OCURLY},
    .{"}", .CCURLY},
    .{":", .COLON},
];

is_symbol :: (x: u8) -> bool {
    return is_alnum(x) || x == #char "_";
}

lexer_chop_token :: (using lexer: *Lexer, token: *Token) -> Lexer_Result {
    lexer_trim_left(lexer);
    while cur < content.count && lexer_starts_with(lexer, "//") {
        lexer_skip_line(lexer);
        lexer_trim_left(lexer);
    }

    memset(token, 0, size_of(Token));
    token.loc = lexer_loc(lexer);
    token.text.data = content.data + cur;
    token.text.count = 0;

    if cur >= content.count return .END;

    for LITERAL_TOKENS {
        if lexer_starts_with(lexer, it.prefix) {
            lexer_skip_char(lexer, it.prefix.count);
            token.kind = it.kind;
            token.text.count += it.prefix.count;
            return .VALID;
        }
    }

    if is_symbol(content[cur]) {
        token.kind = .SYMBOL;
        while cur < content.count && is_symbol(content[cur]) {
            lexer_skip_char(lexer);
            token.text.count += 1;
        }

        if token.text == "for" {
            token.kind = .FOR;
        }

        return .VALID;
    }

    if content[cur] == #char "#" {
        token.kind = .COMMAND;
        lexer_skip_char(lexer);
        token.text.count += 1;
        while cur < content.count && is_symbol(content[cur]) {
            lexer_skip_char(lexer);
            token.text.count += 1;
        }
        return .VALID;
    }

    if content[cur] == #char "'" {
        lexer_skip_char(lexer);
        token.text.data += 1;

        while cur < content.count {
            if content[cur] == {
            case #char "'"; break;
            // TODO: we do not actually unescape the escaped characters
            case #char "\\";
                lexer_skip_char(lexer);
                token.text.count += 1;
                if cur < content.count return .UNCLOSED_STRING;
                lexer_skip_char(lexer);
                token.text.count += 1;
            case;
                lexer_skip_char(lexer);
                token.text.count += 1;
            }
        }

        if cur >= content.count return .UNCLOSED_STRING;
        lexer_skip_char(lexer);
        return .VALID;
    }

    lexer_skip_char(lexer);
    token.text.count += 1;
    return .UNKNOWN;
}

lexer_next :: (using lexer: *Lexer, token: *Token) -> Lexer_Result {
    if peek_full {
        peek_full = false;
        <<token = peek_token;
        return peek_result;
    }
    return lexer_chop_token(lexer, token);
}

lexer_peek :: (using lexer: *Lexer, token: *Token) -> Lexer_Result {
    if !peek_full {
        peek_result = lexer_chop_token(lexer, *peek_token);
        peek_full = true;
    }
    <<token = peek_token;
    return peek_result;
}
