// RegEx module
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const print = std.debug.print;
const allocPrint = std.fmt.allocPrint;

/// RegEx State
const RegExState = struct {
    /// + pattern is currently in a matched state
    plus_matched: bool,
    /// Currently inside a regex
    in_regex: bool = false,
    /// Permanently in regex mode (entire string is regex)
    regex_permanent: bool = false,
};

/// Does the character match numeric?
inline fn match_numeric(c: u8) bool {
    if (c >= '0' and c <= '9') {
        return true;
    } else if (c == '.') {
        return true;
    } else {
        return false;
    }
}

/// RegEx matching (inner function)
fn match_inner(
    regex: []const u8,
    s: []const u8,
    ri1: usize,
    si: usize,
    state: RegExState,
) bool {
    // For debugging
    // if (regex[0] == 'Z') {
    //     print("{d} {d} {c} {c} :: {d} {d}\n", .{
    //         ri,
    //         si,
    //         if (ri < regex.len) regex[ri] else '_',
    //         if (si < s.len) s[si] else '_',
    //         regex.len,
    //         s.len,
    //     });
    // }

    var ri = ri1;
    var in_regex = state.in_regex;
    if (!state.regex_permanent) {
        if (state.in_regex) {
            if (ri + 1 < regex.len and std.mem.eql(u8, regex[ri .. ri + 2], ">>")) {
                in_regex = false;
                ri += 2;
            }
        } else {
            if (ri + 4 < regex.len and std.mem.eql(u8, regex[ri .. ri + 5], "<<re:")) {
                in_regex = true;
                ri += 5;
            }
        }
    }

    // End of regex
    if (ri >= regex.len) {
        return si >= s.len;
    }

    if (!in_regex) {
        // Need to do a direct compare only
        if (regex[ri] == s[si]) {
            return match_inner(
                regex,
                s,
                ri + 1,
                si + 1,
                RegExState{ .plus_matched = false, .in_regex = in_regex, .regex_permanent = state.regex_permanent },
            );
        } else {
            return false;
        }
    }

    // class len: . = 1, \d = 2
    var class_len: usize = 1;
    if (ri + 1 < regex.len and regex[ri] == '\\' and regex[ri + 1] == 'd') {
        class_len = 2;
    }

    // Try to match current char
    var char_matched = false;
    if (si < s.len) {
        if (ri + 1 < regex.len and regex[ri] == '\\' and regex[ri + 1] == 'd' and match_numeric(s[si])) {
            // match digits
            char_matched = true;
        } else if (regex[ri] == s[si]) {
            // matches char exactly
            char_matched = true;
        } else if (regex[ri] == '.') {
            // match any character
            char_matched = true;
        }
    }

    // For debugging
    // if (regex[0] == 'Z') {
    //     print("{d} {d} {c} {c} :: {d} {d} :: {any} {d} :: {any}\n", .{
    //         ri,
    //         si,
    //         if (ri < regex.len) regex[ri] else '_',
    //         if (si < s.len) s[si] else '_',
    //         regex.len,
    //         s.len,
    //         char_matched,
    //         class_len,
    //         (ri + (class_len - 1) + 1 < regex.len),
    //     });
    // }

    if (ri + (class_len - 1) + 1 < regex.len) {
        if (regex[ri + class_len] == '*') {
            // Match *
            if (match_inner(
                regex,
                s,
                ri + class_len + 1,
                si,
                RegExState{ .plus_matched = false, .in_regex = in_regex, .regex_permanent = state.regex_permanent },
            )) {
                // try to match 0 chars
                return true;
            } else if (char_matched) {
                // try to match multiple chars
                return match_inner(
                    regex,
                    s,
                    ri,
                    si + 1,
                    RegExState{ .plus_matched = false, .in_regex = in_regex, .regex_permanent = state.regex_permanent },
                );
            }
        } else if (regex[ri + class_len] == '?') {
            // match ?
            if (match_inner(
                regex,
                s,
                ri + class_len + 1,
                si,
                RegExState{ .plus_matched = false, .in_regex = in_regex, .regex_permanent = state.regex_permanent },
            )) {
                // try to match 0 chars
                return true;
            } else if (char_matched) {
                // try to match 1 char
                return match_inner(
                    regex,
                    s,
                    ri + class_len + 1,
                    si + 1,
                    RegExState{ .plus_matched = false, .in_regex = in_regex, .regex_permanent = state.regex_permanent },
                );
            }
        } else if (regex[ri + class_len] == '+') {
            // match +
            if (state.plus_matched) {
                if (match_inner(
                    regex,
                    s,
                    ri + class_len + 1,
                    si,
                    RegExState{ .plus_matched = true, .in_regex = in_regex, .regex_permanent = state.regex_permanent },
                )) {
                    // already matched, continue by matching 0 chars of the pattern
                    return true;
                }

                if (match_inner(
                    regex,
                    s,
                    ri + class_len + 1,
                    si + 1,
                    RegExState{ .plus_matched = false, .in_regex = in_regex, .regex_permanent = state.regex_permanent },
                )) {
                    // did not match this char, but plus has already been accomplished
                    return true;
                }

                // did not match this char, but plus has already been accomplished
            }

            if (char_matched) {
                // matched this char, keep attempting a match
                return match_inner(
                    regex,
                    s,
                    ri,
                    si + 1,
                    RegExState{ .plus_matched = true, .in_regex = in_regex, .regex_permanent = state.regex_permanent },
                );
            }
        }
    }

    return char_matched and match_inner(
        regex,
        s,
        ri + class_len,
        si + 1,
        RegExState{ .plus_matched = false, .in_regex = in_regex, .regex_permanent = state.regex_permanent },
    );
}

/// RegEx matching
/// A very simple and restricted version.
/// Assumes entire regex is a regex
/// Supported:
/// .? .+ .*
/// \d? \d+ \d*
pub fn match(regex: []const u8, s: []const u8) bool {
    // Check exact match
    if (std.mem.eql(u8, regex, s)) {
        return true;
    }

    // Use regex
    return match_inner(
        regex,
        s,
        0,
        0,
        RegExState{
            .plus_matched = false,
            .in_regex = true,
            .regex_permanent = true,
        },
    );
}

/// String matching that supports embedded regexs
/// A very simple and restricted version.
/// Supported:
/// .? .+ .*
/// \d? \d+ \d*
/// Usage:
/// AAA<<re:BBB>>CCC - Exact matches on AAA and CCC, regex match on BBB
pub fn match_embedded(pattern: []const u8, s: []const u8) bool {
    // Check exact match
    if (std.mem.eql(u8, pattern, s)) {
        return true;
    }

    // Use regex
    return match_inner(
        pattern,
        s,
        0,
        0,
        RegExState{
            .plus_matched = false,
            .in_regex = false,
            .regex_permanent = false,
        },
    );
}

////////
// Tests

test "regex - exact match" {
    const result = match("abc", "abc");
    try std.testing.expect(result);
}

test "regex - match 1 any first" {
    const result = match(".bc", "abc");
    try std.testing.expect(result);
}

test "regex - match 1 any last" {
    const result = match("ab.", "abc");
    try std.testing.expect(result);
}

test "regex - match 1 any middle" {
    const result = match("ab.d", "abcd");
    try std.testing.expect(result);
}

test "regex - match 2 any middle" {
    const result = match("a..d", "abcd");
    try std.testing.expect(result);
}

test "regex - match 1 - failed" {
    const result = match("ab.", "abcd");
    try std.testing.expect(!result);
}

test "regex - match 3 any middle" {
    const result = match("a.*d", "abccd");
    try std.testing.expect(result);
}

test "regex - match 6 any middle" {
    const result = match("a.*d", "aUTWXYZd");
    try std.testing.expect(result);
}

test "regex - match 1? - start" {
    const result = match(".?bc", "abc");
    try std.testing.expect(result);
}

test "regex - match 1? - end" {
    const result = match("ab.?", "abc");
    try std.testing.expect(result);
}

test "regex - match 1? - middle" {
    const result = match("a.?c", "abc");
    try std.testing.expect(result);
}

test "regex - match 0? - start" {
    const result = match(".?bc", "bc");
    try std.testing.expect(result);
}

test "regex - match 0? - end" {
    const result = match("a.?", "a");
    try std.testing.expect(result);
}

test "regex - match 0? - middle" {
    const result = match("a.?c", "ac");
    try std.testing.expect(result);
}

test "regex - match 0? - middle - failed" {
    const result = match("a.?c", "ab");
    try std.testing.expect(!result);
}

test "regex - match 1+ - start" {
    const result = match(".+bc", "abc");
    try std.testing.expect(result);
}

test "regex - match 1+ - end" {
    const result = match("ab.+", "abc");
    try std.testing.expect(result);
}

test "regex - match 1+ - middle" {
    const result = match("a.+c", "abc");
    try std.testing.expect(result);
}

test "regex - match 0+ - start - failure" {
    const result = match(".+bc", "bc");
    try std.testing.expect(!result);
}

test "regex - match 0+ - end - failure" {
    const result = match("a.+", "a");
    try std.testing.expect(!result);
}

test "regex - match 0+ - middle - failure" {
    const result = match("a.+c", "ac");
    try std.testing.expect(!result);
}

test "regex - match \\d*2 - start" {
    const result = match("\\d*cef", "89cef");
    try std.testing.expect(result);
}

test "regex - match \\d*5 - end" {
    const result = match("abc\\d*", "abc12345");
    try std.testing.expect(result);
}

test "regex - match \\d*1 - middle" {
    const result = match("a\\d*cef", "a8cef");
    try std.testing.expect(result);
}

test "regex - match \\d*5 - middle" {
    const result = match("a\\d*cef", "a12345cef");
    try std.testing.expect(result);
}

test "regex - match 1 \\d+ - start" {
    const result = match("\\d+bc", "7bc");
    try std.testing.expect(result);
}

test "regex - match 1 \\d+ - end" {
    const result = match("ab\\d+", "ab3");
    try std.testing.expect(result);
}

test "regex - match 1 \\d+ - middle" {
    const result = match("a\\d+c", "a3c");
    try std.testing.expect(result);
}

test "regex - match 3 \\d+ - start" {
    const result = match("\\d+bc", "789bc");
    try std.testing.expect(result);
}

test "regex - match 3 \\d+ - end" {
    const result = match("ab\\d+", "ab345");
    try std.testing.expect(result);
}

test "regex - match 3 \\d+ - middle" {
    const result = match("a\\d+c", "a345c");
    try std.testing.expect(result);
}

test "regex - match \\d+ - failure" {
    const result = match("a\\d+c", "ac");
    try std.testing.expect(!result);
}

test "regex - match 1 \\d? - start" {
    const result = match("\\d?bc", "5bc");
    try std.testing.expect(result);
}

test "regex - match 1 \\d? - end" {
    const result = match("ab\\d?", "ab8");
    try std.testing.expect(result);
}

test "regex - match 1 \\d? - middle" {
    const result = match("a\\d?c", "a4c");
    try std.testing.expect(result);
}

test "regex - match 0 \\d? - start" {
    const result = match("\\d?bc", "bc");
    try std.testing.expect(result);
}

test "regex - match 0 \\d? - end" {
    const result = match("a\\d?", "a");
    try std.testing.expect(result);
}

test "regex - match 0 \\d? - middle" {
    const result = match("a\\d?c", "ac");
    try std.testing.expect(result);
}

test "regex - match 0 \\d? - middle - failed" {
    const result = match("a\\d?c", "ab");
    try std.testing.expect(!result);
}

test "regex - match \\d+ - with decimal" {
    const result = match("a\\d+c", "a12.345c");
    try std.testing.expect(result);
}

// ---------------

test "regex - embedded - no regex" {
    const result = match_embedded("abc", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - no regex - failure" {
    const result = match_embedded("a.c", "abc");
    try std.testing.expect(!result);
}

test "regex - embedded - exact match" {
    const result = match_embedded("<<re:abc>>", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - match 1 any first" {
    const result = match_embedded("<<re:.bc>>", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - match 1 any last" {
    const result = match_embedded("<<re:ab.>>", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - match 1 any middle" {
    const result = match_embedded("<<re:ab.d>>", "abcd");
    try std.testing.expect(result);
}

test "regex - embedded - match 2 any middle" {
    const result = match_embedded("<<re:a..d>>", "abcd");
    try std.testing.expect(result);
}

test "regex - embedded - match 1 - failed" {
    const result = match_embedded("<<re:ab.>>", "abcd");
    try std.testing.expect(!result);
}

test "regex - embedded - match 3 any middle" {
    const result = match_embedded("<<re:a.*d>>", "abccd");
    try std.testing.expect(result);
}

test "regex - embedded - match 6 any middle" {
    const result = match_embedded("<<re:a.*d>>", "aUTWXYZd");
    try std.testing.expect(result);
}

test "regex - embedded - match 1? - start" {
    const result = match_embedded("<<re:.?bc>>", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - match 1? - end" {
    const result = match_embedded("<<re:ab.?>>", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - match 1? - middle" {
    const result = match_embedded("<<re:a.?c>>", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - match 0? - start" {
    const result = match_embedded("<<re:.?bc>>", "bc");
    try std.testing.expect(result);
}

test "regex - embedded - match 0? - end" {
    const result = match_embedded("<<re:a.?>>", "a");
    try std.testing.expect(result);
}

test "regex - embedded - match 0? - middle" {
    const result = match_embedded("<<re:a.?c>>", "ac");
    try std.testing.expect(result);
}

test "regex - embedded - match 0? - middle - failed" {
    const result = match_embedded("<<re:a.?c>>", "ab");
    try std.testing.expect(!result);
}

test "regex - embedded - match 1+ - start" {
    const result = match_embedded("<<re:.+bc>>", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - match 1+ - end" {
    const result = match_embedded("<<re:ab.+>>", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - match 1+ - middle" {
    const result = match_embedded("<<re:a.+c>>", "abc");
    try std.testing.expect(result);
}

test "regex - embedded - match 0+ - start - failure" {
    const result = match_embedded("<<re:.+bc>>", "bc");
    try std.testing.expect(!result);
}

test "regex - embedded - match 0+ - end - failure" {
    const result = match_embedded("<<re:a.+>>", "a");
    try std.testing.expect(!result);
}

test "regex - embedded - match 0+ - middle - failure" {
    const result = match_embedded("<<re:a.+c>>", "ac");
    try std.testing.expect(!result);
}

test "regex - embedded - match \\d*2 - start" {
    const result = match_embedded("<<re:\\d*cef>>", "89cef");
    try std.testing.expect(result);
}

test "regex - embedded - match \\d*5 - end" {
    const result = match_embedded("<<re:abc\\d*>>", "abc12345");
    try std.testing.expect(result);
}

test "regex - embedded - match \\d*1 - middle" {
    const result = match_embedded("<<re:a\\d*cef>>", "a8cef");
    try std.testing.expect(result);
}

test "regex - embedded - match \\d*5 - middle" {
    const result = match_embedded("<<re:a\\d*cef>>", "a12345cef");
    try std.testing.expect(result);
}

test "regex - embedded - match 1 \\d+ - start" {
    const result = match_embedded("<<re:\\d+bc>>", "7bc");
    try std.testing.expect(result);
}

test "regex - embedded - match 1 \\d+ - end" {
    const result = match_embedded("<<re:ab\\d+>>", "ab3");
    try std.testing.expect(result);
}

test "regex - embedded - match 1 \\d+ - middle" {
    const result = match_embedded("<<re:a\\d+c>>", "a3c");
    try std.testing.expect(result);
}

test "regex - embedded - match 3 \\d+ - start" {
    const result = match_embedded("<<re:\\d+bc>>", "789bc");
    try std.testing.expect(result);
}

test "regex - embedded - match 3 \\d+ - end" {
    const result = match_embedded("<<re:ab\\d+>>", "ab345");
    try std.testing.expect(result);
}

test "regex - embedded - match 3 \\d+ - middle" {
    const result = match_embedded("<<re:a\\d+c>>", "a345c");
    try std.testing.expect(result);
}

test "regex - embedded - match \\d+ - failure" {
    const result = match_embedded("<<re:a\\d+c>>", "ac");
    try std.testing.expect(!result);
}

test "regex - embedded - match 1 \\d? - start" {
    const result = match_embedded("<<re:\\d?bc>>", "5bc");
    try std.testing.expect(result);
}

test "regex - embedded - match 1 \\d? - end" {
    const result = match_embedded("<<re:ab\\d?>>", "ab8");
    try std.testing.expect(result);
}

test "regex - embedded - match 1 \\d? - middle" {
    const result = match_embedded("<<re:a\\d?c>>", "a4c");
    try std.testing.expect(result);
}

test "regex - embedded - match 0 \\d? - start" {
    const result = match_embedded("<<re:\\d?bc>>", "bc");
    try std.testing.expect(result);
}

test "regex - embedded - match 0 \\d? - end" {
    const result = match_embedded("<<re:a\\d?>>", "a");
    try std.testing.expect(result);
}

test "regex - embedded - match 0 \\d? - middle" {
    const result = match_embedded("<<re:a\\d?c>>", "ac");
    try std.testing.expect(result);
}

test "regex - embedded - match 0 \\d? - middle - failed" {
    const result = match_embedded("<<re:a\\d?c>>", "ab");
    try std.testing.expect(!result);
}

test "regex - embedded - match \\d+ - with decimal" {
    const result = match_embedded("<<re:a\\d+c>>", "a12.345c");
    try std.testing.expect(result);
}

test "regex - embedded - match \\d+ - with number and outside ?" {
    const result = match_embedded("abc?def<<re:g\\d+h>>ij", "abc?defg123hij");
    try std.testing.expect(result);
}
