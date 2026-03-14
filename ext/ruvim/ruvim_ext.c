#include "ruby.h"
#include "ruby/encoding.h"

/* ------------------------------------------------------------------ */
/* Unicode width tables                                                */
/* ------------------------------------------------------------------ */

typedef struct {
    unsigned int lo;
    unsigned int hi;
} range_t;

static const range_t combining_ranges[] = {
    {0x0300, 0x036F},
    {0x1AB0, 0x1AFF},
    {0x1DC0, 0x1DFF},
    {0x20D0, 0x20FF},
    {0xFE20, 0xFE2F},
};
#define COMBINING_COUNT (sizeof(combining_ranges) / sizeof(combining_ranges[0]))

static const range_t zero_width_ranges[] = {
    {0x200D, 0x200D},
    {0xFE00, 0xFE0F},
    {0xE0100, 0xE01EF},
};
#define ZERO_WIDTH_COUNT (sizeof(zero_width_ranges) / sizeof(zero_width_ranges[0]))

static const range_t wide_ranges[] = {
    {0x1100, 0x115F},
    {0x2329, 0x232A},
    {0x2E80, 0xA4CF},
    {0xAC00, 0xD7A3},
    {0xF900, 0xFAFF},
    {0xFE10, 0xFE19},
    {0xFE30, 0xFE6F},
    {0xFF00, 0xFF60},
    {0xFFE0, 0xFFE6},
    {0x20000, 0x323AF},
};
#define WIDE_COUNT (sizeof(wide_ranges) / sizeof(wide_ranges[0]))

static const range_t emoji_ranges[] = {
    {0x2600, 0x27BF},
    {0x1F300, 0x1FAFF},
};
#define EMOJI_COUNT (sizeof(emoji_ranges) / sizeof(emoji_ranges[0]))

static const range_t ambiguous_ranges[] = {
    {0x00A1, 0x00A1},
    {0x00A4, 0x00A4},
    {0x00A7, 0x00A8},
    {0x00AA, 0x00AA},
    {0x00AD, 0x00AE},
    {0x00B0, 0x00B4},
    {0x00B6, 0x00BA},
    {0x00BC, 0x00BF},
    {0x0391, 0x03A9},
    {0x03B1, 0x03C9},
    {0x2010, 0x2010},
    {0x2013, 0x2016},
    {0x2018, 0x2019},
    {0x201C, 0x201D},
    {0x2020, 0x2022},
    {0x2024, 0x2027},
    {0x2030, 0x2030},
    {0x2032, 0x2033},
    {0x2035, 0x2035},
    {0x203B, 0x203B},
    {0x203E, 0x203E},
    {0x2460, 0x24E9},
    {0x2500, 0x257F},
};
#define AMBIGUOUS_COUNT (sizeof(ambiguous_ranges) / sizeof(ambiguous_ranges[0]))

static inline int
in_ranges(unsigned int code, const range_t *ranges, int count)
{
    for (int i = 0; i < count; i++) {
        if (code < ranges[i].lo) return 0;  /* sorted — early exit */
        if (code <= ranges[i].hi) return 1;
    }
    return 0;
}

static int ambiguous_width = 1;

static int
codepoint_width(unsigned int code)
{
    if (code == 0) return 0;
    if (code < 0x20) return 1;      /* control → 1 (caller handles display) */
    if (code < 0x7F) return 1;      /* printable ASCII */
    if (in_ranges(code, combining_ranges, COMBINING_COUNT)) return 0;
    if (in_ranges(code, zero_width_ranges, ZERO_WIDTH_COUNT)) return 0;
    if (in_ranges(code, ambiguous_ranges, AMBIGUOUS_COUNT)) return ambiguous_width;
    if (in_ranges(code, emoji_ranges, EMOJI_COUNT)) return 2;
    if (in_ranges(code, wide_ranges, WIDE_COUNT)) return 2;
    return 1;
}

/* ------------------------------------------------------------------ */
/* Ruby method: cell_width(ch, col: 0, tabstop: 2)                    */
/* ------------------------------------------------------------------ */

static VALUE
rb_cell_width(int argc, VALUE *argv, VALUE self)
{
    VALUE ch, opts;
    rb_scan_args(argc, argv, "1:", &ch, &opts);

    if (NIL_P(ch) || (TYPE(ch) == T_STRING && RSTRING_LEN(ch) == 0))
        return INT2FIX(1);

    int col = 0, tabstop = 2;
    if (!NIL_P(opts)) {
        VALUE v;
        static ID id_col, id_tabstop;
        if (!id_col) {
            id_col = rb_intern("col");
            id_tabstop = rb_intern("tabstop");
        }
        v = rb_hash_lookup2(opts, ID2SYM(id_col), Qnil);
        if (!NIL_P(v)) col = NUM2INT(v);
        v = rb_hash_lookup2(opts, ID2SYM(id_tabstop), Qnil);
        if (!NIL_P(v)) tabstop = NUM2INT(v);
    }

    if (TYPE(ch) != T_STRING) return INT2FIX(1);

    const char *ptr = RSTRING_PTR(ch);
    long len = RSTRING_LEN(ch);

    if (len == 1 && ptr[0] == '\t') {
        int w = tabstop - (col % tabstop);
        if (w == 0) w = tabstop;
        return INT2FIX(w);
    }

    /* Fast path: single-byte ASCII */
    if (len == 1) return INT2FIX(1);

    /* Decode first codepoint */
    unsigned int code = rb_enc_codepoint_len(ptr, ptr + len, NULL,
                                              rb_utf8_encoding());
    return INT2FIX(codepoint_width(code));
}

/* ------------------------------------------------------------------ */
/* Ruby method: display_width(str, tabstop: 2, start_col: 0)          */
/* ------------------------------------------------------------------ */

static VALUE
rb_display_width(int argc, VALUE *argv, VALUE self)
{
    VALUE str, opts;
    rb_scan_args(argc, argv, "1:", &str, &opts);

    int tabstop = 2, start_col = 0;
    if (!NIL_P(opts)) {
        VALUE v;
        static ID id_tabstop, id_start_col;
        if (!id_tabstop) {
            id_tabstop = rb_intern("tabstop");
            id_start_col = rb_intern("start_col");
        }
        v = rb_hash_lookup2(opts, ID2SYM(id_tabstop), Qnil);
        if (!NIL_P(v)) tabstop = NUM2INT(v);
        v = rb_hash_lookup2(opts, ID2SYM(id_start_col), Qnil);
        if (!NIL_P(v)) start_col = NUM2INT(v);
    }

    if (NIL_P(str)) str = rb_str_new("", 0);
    if (TYPE(str) != T_STRING) str = rb_String(str);

    const char *ptr = RSTRING_PTR(str);
    const char *end = ptr + RSTRING_LEN(str);
    rb_encoding *enc = rb_utf8_encoding();
    int col = start_col;

    while (ptr < end) {
        unsigned int code;
        int clen = rb_enc_precise_mbclen(ptr, end, enc);

        if (!MBCLEN_CHARFOUND_P(clen)) {
            /* invalid byte — skip one byte, width 1 */
            ptr++;
            col++;
            continue;
        }
        clen = MBCLEN_CHARFOUND_LEN(clen);
        code = rb_enc_codepoint(ptr, end, enc);
        ptr += clen;

        if (code == '\t') {
            int w = tabstop - (col % tabstop);
            if (w == 0) w = tabstop;
            col += w;
        } else if (clen == 1) {
            col++;  /* ASCII */
        } else {
            col += codepoint_width(code);
        }
    }

    return INT2FIX(col - start_col);
}

/* ------------------------------------------------------------------ */
/* Ruby method: expand_tabs(str, tabstop: 2, start_col: 0)            */
/* ------------------------------------------------------------------ */

static VALUE
rb_expand_tabs(int argc, VALUE *argv, VALUE self)
{
    VALUE str, opts;
    rb_scan_args(argc, argv, "1:", &str, &opts);

    int tabstop = 2, start_col = 0;
    if (!NIL_P(opts)) {
        VALUE v;
        static ID id_tabstop, id_start_col;
        if (!id_tabstop) {
            id_tabstop = rb_intern("tabstop");
            id_start_col = rb_intern("start_col");
        }
        v = rb_hash_lookup2(opts, ID2SYM(id_tabstop), Qnil);
        if (!NIL_P(v)) tabstop = NUM2INT(v);
        v = rb_hash_lookup2(opts, ID2SYM(id_start_col), Qnil);
        if (!NIL_P(v)) start_col = NUM2INT(v);
    }

    if (NIL_P(str)) str = rb_str_new("", 0);
    if (TYPE(str) != T_STRING) str = rb_String(str);

    const char *ptr = RSTRING_PTR(str);
    const char *end = ptr + RSTRING_LEN(str);
    rb_encoding *enc = rb_utf8_encoding();
    int col = start_col;

    VALUE out = rb_str_buf_new(RSTRING_LEN(str) + 32);
    rb_enc_associate(out, enc);

    while (ptr < end) {
        if (*ptr == '\t') {
            int w = tabstop - (col % tabstop);
            if (w == 0) w = tabstop;
            for (int i = 0; i < w; i++)
                rb_str_cat(out, " ", 1);
            col += w;
            ptr++;
        } else {
            int clen = rb_enc_precise_mbclen(ptr, end, enc);
            if (!MBCLEN_CHARFOUND_P(clen)) {
                rb_str_cat(out, ptr, 1);
                ptr++;
                col++;
                continue;
            }
            clen = MBCLEN_CHARFOUND_LEN(clen);
            unsigned int code = rb_enc_codepoint(ptr, end, enc);
            rb_str_cat(out, ptr, clen);
            col += (clen == 1) ? 1 : codepoint_width(code);
            ptr += clen;
        }
    }

    return out;
}

/* ------------------------------------------------------------------ */
/* Ruby method: set_ambiguous_width(w)                                 */
/* ------------------------------------------------------------------ */

static VALUE
rb_set_ambiguous_width(VALUE self, VALUE w)
{
    ambiguous_width = NUM2INT(w);
    return w;
}

/* ------------------------------------------------------------------ */
/* TextMetrics                                                         */
/* ------------------------------------------------------------------ */

static VALUE cCell = Qundef;  /* RuVim::TextMetrics::Cell (lazy) */

static VALUE
get_cell_class(void)
{
    if (cCell == Qundef) {
        VALUE mRuVim = rb_const_get(rb_cObject, rb_intern("RuVim"));
        VALUE mTM = rb_const_get(mRuVim, rb_intern("TextMetrics"));
        cCell = rb_const_get(mTM, rb_intern("Cell"));
        rb_gc_register_address(&cCell);
    }
    return cCell;
}

/* clip_cells_for_width(text, width, source_col_start: 0, tabstop: 2)
 * Returns [cells_array, display_col] */
static VALUE
rb_clip_cells_for_width(int argc, VALUE *argv, VALUE self)
{
    VALUE text, v_width, opts;
    rb_scan_args(argc, argv, "2:", &text, &v_width, &opts);

    int max_width = NUM2INT(v_width);
    if (max_width < 0) max_width = 0;
    int source_col_start = 0, tabstop = 2;

    if (!NIL_P(opts)) {
        VALUE v;
        static ID id_source_col_start, id_tabstop;
        if (!id_source_col_start) {
            id_source_col_start = rb_intern("source_col_start");
            id_tabstop = rb_intern("tabstop");
        }
        v = rb_hash_lookup2(opts, ID2SYM(id_source_col_start), Qnil);
        if (!NIL_P(v)) source_col_start = NUM2INT(v);
        v = rb_hash_lookup2(opts, ID2SYM(id_tabstop), Qnil);
        if (!NIL_P(v)) tabstop = NUM2INT(v);
    }

    if (NIL_P(text)) text = rb_str_new("", 0);
    if (TYPE(text) != T_STRING) text = rb_String(text);

    const char *ptr = RSTRING_PTR(text);
    const char *end = ptr + RSTRING_LEN(text);
    rb_encoding *enc = rb_utf8_encoding();

    VALUE cell_class = get_cell_class();
    static ID id_new = 0;
    if (!id_new) id_new = rb_intern("new");

    VALUE cells = rb_ary_new();
    int display_col = 0;
    int source_col = source_col_start;
    VALUE space_str = rb_str_new(" ", 1);
    VALUE question_str = rb_str_new("?", 1);

    while (ptr < end) {
        int clen = rb_enc_precise_mbclen(ptr, end, enc);
        if (!MBCLEN_CHARFOUND_P(clen)) {
            /* invalid byte */
            if (display_col >= max_width) break;
            rb_ary_push(cells, rb_funcall(cell_class, id_new, 3,
                        question_str, INT2FIX(source_col), INT2FIX(1)));
            display_col++;
            source_col++;
            ptr++;
            continue;
        }
        clen = MBCLEN_CHARFOUND_LEN(clen);
        unsigned int code = rb_enc_codepoint(ptr, end, enc);

        /* Printable ASCII fast path */
        if (code >= 0x20 && code <= 0x7E) {
            if (display_col >= max_width) break;
            VALUE ch = rb_str_new(ptr, 1);
            rb_ary_push(cells, rb_funcall(cell_class, id_new, 3,
                        ch, INT2FIX(source_col), INT2FIX(1)));
            display_col++;
            source_col++;
            ptr += 1;
            continue;
        }

        /* Tab */
        if (code == '\t') {
            int w = tabstop - (display_col % tabstop);
            if (w == 0) w = tabstop;
            if (display_col + w > max_width) break;
            for (int i = 0; i < w; i++) {
                rb_ary_push(cells, rb_funcall(cell_class, id_new, 3,
                            space_str, INT2FIX(source_col), INT2FIX(1)));
            }
            display_col += w;
            source_col++;
            ptr += 1;
            continue;
        }

        /* Control chars */
        if (code < 0x20 || code == 0x7F || (code >= 0x80 && code <= 0x9F)) {
            if (display_col >= max_width) break;
            rb_ary_push(cells, rb_funcall(cell_class, id_new, 3,
                        question_str, INT2FIX(source_col), INT2FIX(1)));
            display_col++;
            source_col++;
            ptr += clen;
            continue;
        }

        /* Multi-byte character */
        int w = codepoint_width(code);
        if (display_col + w > max_width) break;
        VALUE ch = rb_enc_str_new(ptr, clen, enc);
        rb_ary_push(cells, rb_funcall(cell_class, id_new, 3,
                    ch, INT2FIX(source_col), INT2FIX(w)));
        display_col += w;
        source_col++;
        ptr += clen;
    }

    VALUE result = rb_ary_new_capa(2);
    rb_ary_push(result, cells);
    rb_ary_push(result, INT2FIX(display_col));
    return result;
}

/* char_index_for_screen_col(line, target_screen_col, tabstop: 2, align: :floor)
 * Returns a character index whose screen column is <= target. */
static VALUE
rb_char_index_for_screen_col(int argc, VALUE *argv, VALUE self)
{
    VALUE line, v_target, opts;
    rb_scan_args(argc, argv, "2:", &line, &v_target, &opts);

    int tabstop = 2;
    int align_ceil = 0;

    if (!NIL_P(opts)) {
        VALUE v;
        static ID id_tabstop, id_align, id_ceil;
        if (!id_tabstop) {
            id_tabstop = rb_intern("tabstop");
            id_align = rb_intern("align");
            id_ceil = rb_intern("ceil");
        }
        v = rb_hash_lookup2(opts, ID2SYM(id_tabstop), Qnil);
        if (!NIL_P(v)) tabstop = NUM2INT(v);
        v = rb_hash_lookup2(opts, ID2SYM(id_align), Qnil);
        if (!NIL_P(v) && SYM2ID(v) == id_ceil) align_ceil = 1;
    }

    if (NIL_P(line)) line = rb_str_new("", 0);
    if (TYPE(line) != T_STRING) line = rb_String(line);

    int target = NUM2INT(v_target);
    if (target < 0) target = 0;

    const char *ptr = RSTRING_PTR(line);
    const char *end = ptr + RSTRING_LEN(line);
    rb_encoding *enc = rb_utf8_encoding();
    int screen_col = 0;
    int char_index = 0;

    /* Walk grapheme clusters using oniguruma regex \X */
    /* Simplified: walk codepoints, treating combining marks as part of
       the previous character (width 0 doesn't advance screen_col). */
    while (ptr < end) {
        /* Measure one grapheme cluster: base char + combining marks */
        int cluster_width = 0;
        int cluster_chars = 0;
        int first = 1;

        while (ptr < end) {
            int clen = rb_enc_precise_mbclen(ptr, end, enc);
            if (!MBCLEN_CHARFOUND_P(clen)) {
                if (first) { ptr++; cluster_chars++; cluster_width = 1; }
                break;
            }
            clen = MBCLEN_CHARFOUND_LEN(clen);
            unsigned int code = rb_enc_codepoint(ptr, end, enc);

            if (!first) {
                /* Check if combining/zero-width — part of cluster */
                int w = codepoint_width(code);
                if (w == 0) {
                    ptr += clen;
                    cluster_chars += (clen == 1 ? 1 : 1);
                    continue;
                }
                break;  /* new base character — end of cluster */
            }

            first = 0;
            ptr += clen;
            cluster_chars += (clen == 1 ? 1 : 1);

            if (code == '\t') {
                int w = tabstop - (screen_col % tabstop);
                if (w == 0) w = tabstop;
                cluster_width = w;
            } else {
                cluster_width = (clen == 1 && code >= 0x20 && code < 0x7F)
                                ? 1 : codepoint_width(code);
            }
        }

        if (screen_col + cluster_width > target) {
            return INT2FIX(align_ceil ? char_index + cluster_chars : char_index);
        }
        screen_col += cluster_width;
        char_index += cluster_chars;
    }

    return INT2FIX(char_index);
}

/* ------------------------------------------------------------------ */
/* Init                                                                */
/* ------------------------------------------------------------------ */

void
Init_ruvim_ext(void)
{
    VALUE mRuVim = rb_define_module("RuVim");
    VALUE mDW = rb_define_module_under(mRuVim, "DisplayWidthExt");

    rb_define_module_function(mDW, "cell_width", rb_cell_width, -1);
    rb_define_module_function(mDW, "display_width", rb_display_width, -1);
    rb_define_module_function(mDW, "expand_tabs", rb_expand_tabs, -1);
    rb_define_module_function(mDW, "set_ambiguous_width", rb_set_ambiguous_width, 1);

    VALUE mTM = rb_define_module_under(mRuVim, "TextMetricsExt");
    rb_define_module_function(mTM, "clip_cells_for_width", rb_clip_cells_for_width, -1);
    rb_define_module_function(mTM, "char_index_for_screen_col", rb_char_index_for_screen_col, -1);
}
