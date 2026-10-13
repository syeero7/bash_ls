const ts = @import("tree_sitter");

extern fn tree_sitter_bash() callconv(.c) *ts.Language;

pub fn getLang() *ts.Language {
    return tree_sitter_bash();
}
