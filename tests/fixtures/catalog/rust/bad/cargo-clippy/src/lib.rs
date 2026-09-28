//! A needless return, which clippy denies under -D warnings.

/// Returns the sum of `a` and `b`.
pub fn add(a: i32, b: i32) -> i32 {
    return a + b;
}
