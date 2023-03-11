typedef struct {
    String_View file_path;
    size_t row, col;
} Loc;

#define Loc_Fmt SV_Fmt":%zu:%zu"
#define Loc_Arg(l) SV_Arg((l).file_path), (l).row, (l).col

typedef enum {
    TK_SYMBOL = 0,
    TK_COMMAND,
    TK_ARROW,
    TK_OBRACKET,
    TK_CBRACKET,
    TK_EQUALS,
    TK_OCURLY,
    TK_CCURLY,
    TK_FOR,
    TK_COLON,
    COUNT_TK,
} Token_Kind;

static_assert(COUNT_TK <= 64, "Can't fit this many tokens into a 64 bit mask");
typedef uint64_t Token_Mask;

#define MASK(t) (1<<(t))

const char *token_kind_display(Token_Kind kind, const char *file_path, size_t line)
{
    switch (kind) {
    case TK_SYMBOL: return "SYMBOL";
    case TK_COMMAND: return "COMMAND";
    case TK_ARROW: return "ARROW";
    case TK_OBRACKET: return "OBRACKET";
    case TK_CBRACKET: return "CBRACKET";
    case TK_EQUALS: return "EQUALS";
    case TK_OCURLY: return "OCURLY";
    case TK_CCURLY: return "CCURLY";
    case TK_FOR: return "FOR";
    case TK_COLON: return "COLON";
    default: {
        printf("%s:%zu: Called in here\n", file_path, line);
        UNREACHABLE("Unknown Token_Kind %d", kind);
    }
    }
}

typedef struct {
    Token_Kind kind;
    Loc loc;
    String_View text;
} Token;

typedef enum {
    LR_VALID,
    LR_END,
    LR_UNCLOSED_STRING,
    LR_UNKNOWN,
} Lexer_Result;

const char *lexer_result_display(Lexer_Result result)
{
    switch (result) {
    case LR_VALID: return "VALID";
    case LR_END: return "END";
    case LR_UNCLOSED_STRING: return "UNCLOSED_STRING";
    case LR_UNKNOWN: return "UNKNOWN";
    }
    UNREACHABLE("Unknown Lexer_Result");
}

typedef struct {
    // TODO: lexer does not handle Unicode
    String_View content;
    String_View file_path;
    size_t cur, bol, row;
    Token peek_token;
    Lexer_Result peek_result;
    bool peek_full;
} Lexer;

typedef struct {
    String_View prefix;
    Token_Kind kind;
} Literal_Token;

static Literal_Token LITERAL_TOKENS[] = {
    {SV_STATIC("<-"), TK_ARROW},
    {SV_STATIC("->"), TK_ARROW},
    {SV_STATIC("["),  TK_OBRACKET},
    {SV_STATIC("]"),  TK_CBRACKET},
    {SV_STATIC("="),  TK_EQUALS},
    {SV_STATIC("{"),  TK_OCURLY},
    {SV_STATIC("}"),  TK_CCURLY},
    {SV_STATIC(":"),  TK_COLON},
};
#define LITERAL_TOKENS_COUNT (sizeof(LITERAL_TOKENS)/sizeof(LITERAL_TOKENS[0]))

Lexer lexer_from_string(String_View content, String_View file_path) {
    return (Lexer) {
        .file_path = file_path,
        .content = content,
    };
}

bool is_symbol(char x)
{
    return isalnum(x) || x == '_';
}

void lexer_skip_char(Lexer *l, size_t n)
{
    assert(l->cur < l->content.count);
    for (size_t i = 0; i < n; ++i) {
        char x = l->content.data[l->cur];
        l->cur += 1;
        if (x == '\n') {
            l->bol = l->cur;
            l->row += 1;
        }
    }
}

void lexer_trim_left(Lexer *l)
{
    while (l->cur < l->content.count && isspace(l->content.data[l->cur])) {
        lexer_skip_char(l, 1);
    }
}

bool lexer_starts_with(Lexer *l, String_View prefix)
{
    String_View slice = sv_from_parts(l->content.data + l->cur, l->content.count - l->cur);
    return sv_starts_with(slice, prefix);
}

void lexer_skip_line(Lexer *l)
{
    while (l->cur < l->content.count && l->content.data[l->cur] != '\n') {
        lexer_skip_char(l, 1);
    }
    if (l->cur < l->content.count) lexer_skip_char(l, 1);
}

Loc lexer_loc(Lexer *l)
{
    return (Loc){
        .file_path = l->file_path,
        .row = l->row + 1,
        .col = l->cur - l->bol + 1,
    };
}

Lexer_Result lexer_chop_token(Lexer *l, Token *t) {
    memset(t, 0, sizeof(*t));

    lexer_trim_left(l);
    while (l->cur < l->content.count && lexer_starts_with(l, SV("//"))) {
        lexer_skip_line(l);
        lexer_trim_left(l);
    }

    t->loc = lexer_loc(l);
    t->text.data = l->content.data + l->cur;
    t->text.count = 0;

    if (l->cur >= l->content.count) return LR_END;

    for (size_t i = 0; i < LITERAL_TOKENS_COUNT; ++i) {
        Literal_Token it = LITERAL_TOKENS[i];
        if (lexer_starts_with(l, it.prefix)) {
            lexer_skip_char(l, it.prefix.count);
            t->kind = it.kind;
            t->text.count += it.prefix.count;
            return LR_VALID;
        }
    }

    if (is_symbol(l->content.data[l->cur])) {
        t->kind = TK_SYMBOL;
        while (l->cur < l->content.count && is_symbol(l->content.data[l->cur])) {
            lexer_skip_char(l, 1);
            t->text.count += 1;
        }

        if (sv_eq(t->text, SV("for"))) {
            t->kind = TK_FOR;
        }

        return LR_VALID;
    }

    if (l->content.data[l->cur] == '#') {
        t->kind = TK_COMMAND;
        lexer_skip_char(l, 1);
        t->text.count += 1;
        while (l->cur < l->content.count && is_symbol(l->content.data[l->cur])) {
            lexer_skip_char(l, 1);
            t->text.count += 1;
        }
        return LR_VALID;
    }

    if (l->content.data[l->cur] == '\'') {
        t->kind = TK_SYMBOL;
        lexer_skip_char(l, 1);
        t->text.data += 1;

        while (l->cur < l->content.count) {
            switch (l->content.data[l->cur]) {
            case '\'': goto closed;
            // TODO: we do not actually unescape the escaped characters
            case '\\': {
                lexer_skip_char(l, 1);
                t->text.count += 1;
                if (l->cur < l->content.count) return LR_UNCLOSED_STRING;
                lexer_skip_char(l, 1);
                t->text.count += 1;
            } break;
            default:
                lexer_skip_char(l, 1);
                t->text.count += 1;
            }
        }
closed:

        if (l->cur >= l->content.count) return LR_UNCLOSED_STRING;
        lexer_skip_char(l, 1);
        return LR_VALID;
    }

    lexer_skip_char(l, 1);
    t->text.count += 1;
    return LR_UNKNOWN;
}

Lexer_Result lexer_next(Lexer *l, Token *t) {
    if (l->peek_full) {
        l->peek_full = false;
        *t = l->peek_token;
        return l->peek_result;
    }
    return lexer_chop_token(l, t);
}

Lexer_Result lexer_peek(Lexer *l, Token *t) {
    if (!l->peek_full) {
        l->peek_result = lexer_chop_token(l, &l->peek_token);
        l->peek_full = true;
    }
    *t = l->peek_token;
    return l->peek_result;
}
