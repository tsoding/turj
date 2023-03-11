#include <assert.h>
#include <stdio.h>
#include <errno.h>

typedef int Errno;

#define UNIMPLEMENTED(...) \
    do { \
        fprintf(stderr, "%s:%d: UNIMPLEMENTED: ", __FILE__, __LINE__); \
        fprintf(stderr, __VA_ARGS__); \
        fprintf(stderr, "\n"); \
        exit(1); \
    } while(0)
#define UNREACHABLE(...) \
    do { \
        fprintf(stderr, "%s:%d: UNREACHABLE: ", __FILE__, __LINE__); \
        fprintf(stderr, __VA_ARGS__); \
        fprintf(stderr, "\n"); \
        exit(1); \
    } while(0)
#define UNUSED(x) (void)(x)
#define return_defer(value) do { result = (value); goto defer; } while (0)

// # Dynamic Array
//
// ## Quick Start
//
// ```c
// typedef struct {
//     int *data;
//     size_t capacity;
//     size_t count;
// } Xs;
//
// Xs xs = {0};
// for (int i = 0; i < 10; ++i) {
//     da_append(&xs, &i);
// }
// ```
#define DA_INIT_CAP 32

#define da_append(da, item)                                           \
    do {                                                              \
        if ((da)->count >= (da)->capacity) {                          \
            size_t new_capacity = (da)->capacity*2;                   \
            if (new_capacity == 0) {                                  \
                new_capacity = DA_INIT_CAP;                           \
            }                                                         \
                                                                      \
            (da)->data = realloc((da)->data,                          \
                                 new_capacity*sizeof((da)->data[0])); \
            (da)->capacity = new_capacity;                            \
        }                                                             \
                                                                      \
        (da)->data[(da)->count++] = (item);                           \
    } while (0)

#define da_append_many(da, new_data, new_data_count)                                    \
    do {                                                                                \
        if ((da)->count + new_data_count > (da)->capacity) {                            \
            if ((da)->capacity == 0) {                                                  \
                (da)->capacity = DA_INIT_CAP;                                           \
            }                                                                           \
            while ((da)->count + new_data_count > (da)->capacity) {                     \
                (da)->capacity *= 2;                                                    \
            }                                                                           \
            (da)->data = realloc((da)->data, (da)->capacity*sizeof(*(da)->data));       \
            assert((da)->data != NULL && "Buy more RAM lol");                           \
        }                                                                               \
        memcpy((da)->data + (da)->count, new_data, new_data_count*sizeof(*(da)->data)); \
        (da)->count += new_data_count;                                                  \
    } while (0)

typedef struct {
    char *data;
    size_t count;
    size_t capacity;
} String_Builder;

#define SB_Fmt "%.*s"
#define SB_Arg(sb) (int) (sb).count, (sb).data

#define sb_append_buf da_append_many
#define sb_append_cstr(sb, cstr)  \
    do {                          \
        const char *s = (cstr);   \
        size_t n = strlen(s);     \
        da_append_many(sb, s, n); \
    } while (0)
#define sb_append_null(sb) da_append_many(sb, "", 1)

#define sb_to_sv(sb) sv_from_parts((sb).data, (sb).count)

#define SV_IMPLEMENTATION
#include "sv.h"
#include "lexer.c"

// TODO: compound symbols

typedef struct {
    Token *data;
    size_t count;
    size_t capacity;
} Tokens;

typedef struct {
    Token state;
    Token read;
    Token write;
    Token step;
    Token next;
} Rule;

typedef struct {
    Rule *data;
    size_t count;
    size_t capacity;
} Rules;

typedef struct {
    Token name;
    Tokens items;
} Set;

typedef struct {
    Set *data;
    size_t count;
    size_t capacity;
} Sets;

typedef struct {
    Token state;
    Tokens tape;
    Token init;
    Loc loc;
} Run;

typedef struct {
    Run *data;
    size_t count;
    size_t capacity;
} Runs;

typedef struct {
    Rules rules;
    Sets sets;
    Runs runs;
} Top_Level;


bool lexer_expect_token_(Lexer *l, Token *t, Token_Mask mask)
{
    Lexer_Result result = lexer_next(l, t);
    switch (result) {
        case LR_VALID: {
            for (Token_Kind kind = 0; kind < COUNT_TK; ++kind) {
                if (!(mask&(1<<kind))) continue;
                if (t->kind == kind) return true;
            }

            String_Builder sb = {0};
            for (Token_Kind kind = 0; kind < COUNT_TK; ++kind) {
                if (!(mask&(1<<kind))) continue;
                if (kind > 0) sb_append_cstr(&sb, " or ");
                sb_append_cstr(&sb, token_kind_display(kind, __FILE__, __LINE__));
            }

            printf(Loc_Fmt": ERROR: expected "SB_Fmt" but got %s\n",
                   Loc_Arg(t->loc), SB_Arg(sb), token_kind_display(t->kind, __FILE__, __LINE__));
            return false;
        } break;
        case LR_END:
        case LR_UNCLOSED_STRING:
        case LR_UNKNOWN: {
            String_Builder sb = {0};
            for (Token_Kind kind = 0; kind < COUNT_TK; ++kind) {
                Token_Kind it = mask&(1<<kind);
                if (!it) continue;
                if (kind > 0) sb_append_cstr(&sb, " or ");
                sb_append_cstr(&sb, token_kind_display(kind, __FILE__, __LINE__));
            }

            printf(Loc_Fmt": ERROR: expected "SB_Fmt" but got %s\n", Loc_Arg(t->loc), SB_Arg(sb), lexer_result_display(result));
            return false;
        } break;

        default: UNREACHABLE("Unexpected Lexer_Result");
    }
}

Rule rule_from_template(Rule temp, Token symbol, Token replace)
{
    Rule instance = temp;
    if (sv_eq(instance.state.text, symbol.text)) instance.state = replace;
    if (sv_eq(instance.read.text, symbol.text)) instance.read = replace;
    if (sv_eq(instance.write.text, symbol.text)) instance.write = replace;
    // TODO: step should be also treated as replacible symbol in the templates
    //if step.text == symbol.text then step = replace;
    if (sv_eq(instance.next.text, symbol.text)) instance.next = replace;
    return instance;
}

bool parse_top_level(Top_Level *tl, Lexer *l)
{
    Token first;
    if (!lexer_expect_token_(l, &first, MASK(TK_SYMBOL) | MASK(TK_COMMAND))) return false;

    switch (first.kind) {
    case TK_COMMAND: {
        if (sv_eq(first.text, SV("#run"))) {
            Run run = {
                .loc = first.loc,
            };

            if (!lexer_expect_token_(l, &run.state, MASK(TK_SYMBOL))) return false;
            if (!lexer_expect_token_(l, &first, MASK(TK_OBRACKET))) return false;

            Lexer_Result result = lexer_next(l, &first);
            while (result == LR_VALID && first.kind != TK_CBRACKET) {
                da_append(&run.tape, first);
                result = lexer_next(l, &first);
            }

            if (result != LR_VALID) {
                printf(Loc_Fmt": ERROR: expected %s but got %s\n", Loc_Arg(first.loc), token_kind_display(TK_CBRACKET, __FILE__, __LINE__), lexer_result_display(result));
                return false;
            } else if (first.kind != TK_CBRACKET) {
                printf(Loc_Fmt": ERROR: expected %s but got %s\n", Loc_Arg(first.loc), token_kind_display(TK_CBRACKET, __FILE__, __LINE__), token_kind_display(first.kind, __FILE__, __LINE__));
                return false;
            }

            if (run.tape.count == 0) {
                printf(Loc_Fmt": ERROR: tape may not be empty, because we are using the last symbol as the symbol the entire infinite tape is initialized with.\n", Loc_Arg(first.loc));
                return false;
            }
            run.init = run.tape.data[run.tape.count - 1];

            da_append(&tl->runs, run);

            return true;
        } else {
            printf(Loc_Fmt": ERROR: unknown command "SV_Fmt"\n", Loc_Arg(first.loc), SV_Arg(first.text));
            return false;
        }
    }
    break;

    case TK_SYMBOL: {
        Token read_or_equal;
        if (!lexer_expect_token_(l, &read_or_equal, MASK(TK_SYMBOL) | MASK(TK_EQUALS))) return false;

        switch (read_or_equal.kind) {
        case TK_SYMBOL: {
            Rule rule = {
                .state = first,
                .read = read_or_equal,
            };
            if (!lexer_expect_token_(l, &rule.write, MASK(TK_SYMBOL))) return false;
            if (!lexer_expect_token_(l, &rule.step, MASK(TK_ARROW))) return false;
            if (!lexer_expect_token_(l, &rule.next, MASK(TK_SYMBOL))) return false;

            Token for_token;
            if (lexer_peek(l, &for_token) == LR_VALID && for_token.kind == TK_FOR) {
                Lexer_Result result = lexer_next(l, &for_token);
                assert(result == LR_VALID);

                Token symbol;
                if (!lexer_expect_token_(l, &symbol, MASK(TK_SYMBOL))) return false;

                Token colon;
                if (!lexer_expect_token_(l, &colon, MASK(TK_COLON))) return false;

                // TODO: introduce the notion of Set expressions and parse the Set expression next in here
                Token set;
                if (!lexer_expect_token_(l, &set, MASK(TK_SYMBOL))) return false;

                // TODO: defer the expansion of `for` so we can define sets anywhere
                for (size_t i = 0; i < tl->sets.count; ++i) {
                    Set *it = &tl->sets.data[i];
                    if (sv_eq(it->name.text, set.text)) {
                        for (size_t j = 0; j < it->items.count; ++j) {
                            Token jt = it->items.data[j];
                            da_append(&tl->rules, rule_from_template(rule, symbol, jt));
                        }
                        return true;
                    }
                }

                // TODO: nested for-s

                printf(Loc_Fmt": ERROR: set "SV_Fmt" does not exist\n", Loc_Arg(set.loc), SV_Arg(set.text));
                return false;
            } else {
                da_append(&tl->rules, rule);
                return true;
            }
        }
        break;

        case TK_EQUALS: {
            Set set = {
                .name = first,
            };

            Token curly;
            if (!lexer_expect_token_(l, &curly, MASK(TK_OCURLY))) return false;

            Token next;
            Lexer_Result result = lexer_next(l, &next);
            while (result == LR_VALID && next.kind == TK_SYMBOL) {
                // TODO: check if the symbols are unique
                da_append(&set.items, next);
                result = lexer_next(l, &next);
            }

            if (result != LR_VALID) {
                printf(Loc_Fmt": ERROR: expected %s but got %s\n", Loc_Arg(next.loc), token_kind_display(TK_CCURLY, __FILE__, __LINE__), lexer_result_display(result));
                return false;
            }

            if (next.kind != TK_CCURLY) {
                printf(Loc_Fmt": ERROR: expected %s but got %s\n", Loc_Arg(next.loc),
                      token_kind_display(TK_CCURLY, __FILE__, __LINE__),
                      token_kind_display(next.kind, __FILE__, __LINE__));
                return false;
            }

            da_append(&tl->sets, set);
            return true;
        }
        break;

        default:
            UNREACHABLE("unexpected token");
        }
    }
    break;

    default:
        UNREACHABLE("unexpected token");
    }
}

void execute_run(Run *run, Rule *rules, size_t rules_count) {
    printf(Loc_Fmt": #run\n", Loc_Arg(run->loc));

    int head = 0;

    while (true) {
        assert(head >= 0);
        while ((size_t) head >= run->tape.count) {
            da_append(&run->tape, run->init);
        }

        String_Builder sb = {0};
        sb_append_buf(&sb, run->state.text.data, run->state.text.count);
        sb_append_cstr(&sb, ":");

        size_t head_start = 0;
        size_t head_end = 0;
        for (size_t i = 0; i < run->tape.count; ++i) {
            Token it = run->tape.data[i];
            if (i == (size_t) head) head_start = sb.count + 1;
            sb_append_cstr(&sb, " ");
            sb_append_buf(&sb, it.text.data, it.text.count);
            if (i == (size_t) head) head_end = sb.count;
        }
        printf(SB_Fmt"\n", SB_Arg(sb));
        for (size_t i = 0; i < head_start; ++i) printf(" ");
        for (size_t i = head_start; i < head_end; ++i) printf("^");
        printf("\n");

        for (size_t i = 0; i < rules_count; ++i) {
            Rule *it = &rules[i];
            if (sv_eq(it->state.text, run->state.text) && sv_eq(it->read.text, run->tape.data[head].text)) {
                run->tape.data[head] = it->write;
                run->state           = it->next;
                if (sv_eq(it->step.text, SV("<-"))) {
                    head -= 1;
                } else if (sv_eq(it->step.text, SV("->"))) {
                    head += 1;
                } else {
                    UNREACHABLE("Unexpected arrow symbol");
                }
                if (head < 0) goto break_loop;
                goto continue_loop;
            }
        }
        goto break_loop;
continue_loop: {}
    }

break_loop:

    printf("-- HALT --\n");
}

Errno file_size(FILE *file, size_t *size)
{
    long saved = ftell(file);
    if (saved < 0) return errno;
    if (fseek(file, 0, SEEK_END) < 0) return errno;
    long result = ftell(file);
    if (result < 0) return errno;
    if (fseek(file, saved, SEEK_SET) < 0) return errno;
    *size = (size_t) result;
    return 0;
}

Errno read_entire_file(const char *file_path, String_Builder *sb)
{
    Errno result = 0;
    FILE *f = NULL;

    f = fopen(file_path, "r");
    if (f == NULL) return_defer(errno);

    size_t size;
    Errno err = file_size(f, &size);
    if (err != 0) return_defer(err);

    if (sb->capacity < size) {
        sb->capacity = size;
        sb->data = realloc(sb->data, sb->capacity*sizeof(*sb->data));
        assert(sb->data != NULL && "Buy more RAM lol");
    }

    fread(sb->data, size, 1, f);
    if (ferror(f)) return_defer(errno);
    sb->count = size;

defer:
    if (f) fclose(f);
    return result;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        printf("Usage: %s <input.turj>\n", argv[0]);
        printf("ERROR: no input was provided\n");
        exit(1);
    }

    const char *file_path = argv[1];
    String_Builder content = {0};
    Errno err = read_entire_file(file_path, &content);
    if (err != 0) {
        printf("ERROR: could not read file %s: %s\n", file_path, strerror(err));
        exit(1);
    }
    Lexer lexer = lexer_from_string(sb_to_sv(content), sv_from_cstr(file_path));

    Top_Level top_level = {0};
    Token first = {0};
    Lexer_Result result = lexer_peek(&lexer, &first);
    while (result == LR_VALID) {
        if (!parse_top_level(&top_level, &lexer)) exit(1);
        result = lexer_peek(&lexer, &first);
    }

    for (size_t i = 0; i < top_level.runs.count; ++i) {
        execute_run(&top_level.runs.data[i], top_level.rules.data, top_level.rules.count);
    }

    return 0;
}
