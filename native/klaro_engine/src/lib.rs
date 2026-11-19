//! Klaro Native Performance Engine
//!
//! Provides a clean C-ABI boundary for Flutter/Dart (`dart:ffi`) covering:
//! 1. High-throughput 64-bit FNV-1a and SHA-256 content hashing (zero external dependencies)
//! 2. Paragraph and sentence-aware RAG text chunking with configurable overlap
//! 3. Fast cosine similarity over Float32 embedding vectors
//! 4. BM25 lexical scoring over document chunks

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::slice;

/// Returns the semantic version of the native engine as a static C string.
#[no_mangle]
pub extern "C" fn klaro_engine_version() -> *const c_char {
    c"1.0.0-rust".as_ptr()
}

/// Frees a C string previously allocated and returned by `klaro_engine`.
///
/// # Safety
/// `ptr` must be either null or a pointer returned by an allocation function
/// in this library (`klaro_chunk_text_json`, `klaro_sha256_hex`).
#[no_mangle]
pub unsafe extern "C" fn klaro_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// Computes a fast 64-bit FNV-1a hash over a byte buffer.
///
/// # Safety
/// `data` must point to at least `len` readable bytes (or be null when `len == 0`).
#[no_mangle]
pub unsafe extern "C" fn klaro_fnv1a64(data: *const u8, len: usize) -> u64 {
    if data.is_null() || len == 0 {
        return 0xcbf29ce484222325;
    }
    let bytes = slice::from_raw_parts(data, len);
    fnv1a64(bytes)
}

pub fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for &b in bytes {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

/// Computes a FIPS 180-4 SHA-256 hex digest of a byte buffer and returns a newly
/// allocated null-terminated C string (must be freed with `klaro_free_string`).
///
/// # Safety
/// `data` must point to at least `len` readable bytes (or be null when `len == 0`).
#[no_mangle]
pub unsafe extern "C" fn klaro_sha256_hex(data: *const u8, len: usize) -> *mut c_char {
    let bytes = if data.is_null() || len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(data, len)
    };
    let hex = sha256_hex(bytes);
    match CString::new(hex) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

pub fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    let bit_len = (data.len() as u64) * 8;
    let mut msg = data.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 {
        msg.push(0x00);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[i * 4],
                chunk[i * 4 + 1],
                chunk[i * 4 + 2],
                chunk[i * 4 + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = String::with_capacity(64);
    const HEX: &[u8; 16] = b"0123456789abcdef";
    for word in h {
        for byte in word.to_be_bytes() {
            out.push(HEX[(byte >> 4) as usize] as char);
            out.push(HEX[(byte & 0x0f) as usize] as char);
        }
    }
    out
}

/// Computes cosine similarity between two `f32` slices of length `len`.
///
/// # Safety
/// `a` and `b` must both point to at least `len` readable `f32` values.
#[no_mangle]
pub unsafe extern "C" fn klaro_cosine_f32(a: *const f32, b: *const f32, len: usize) -> f64 {
    if a.is_null() || b.is_null() || len == 0 {
        return 0.0;
    }
    let sa = slice::from_raw_parts(a, len);
    let sb = slice::from_raw_parts(b, len);
    cosine_f32(sa, sb)
}

pub fn cosine_f32(a: &[f32], b: &[f32]) -> f64 {
    let n = a.len().min(b.len());
    if n == 0 {
        return 0.0;
    }
    let mut dot = 0.0f64;
    let mut na = 0.0f64;
    let mut nb = 0.0f64;
    for i in 0..n {
        let va = a[i] as f64;
        let vb = b[i] as f64;
        dot += va * vb;
        na += va * va;
        nb += vb * vb;
    }
    if na == 0.0 || nb == 0.0 {
        return 0.0;
    }
    dot / (na.sqrt() * nb.sqrt())
}

/// Computes a BM25-inspired lexical overlap score between `query` and `document` C strings.
///
/// # Safety
/// `query` and `document` must be valid null-terminated UTF-8 C strings.
#[no_mangle]
pub unsafe extern "C" fn klaro_bm25_score(
    query: *const c_char,
    document: *const c_char,
) -> f64 {
    if query.is_null() || document.is_null() {
        return 0.0;
    }
    let q = match CStr::from_ptr(query).to_str() {
        Ok(s) => s,
        Err(_) => return 0.0,
    };
    let d = match CStr::from_ptr(document).to_str() {
        Ok(s) => s,
        Err(_) => return 0.0,
    };
    bm25_score(q, d)
}

pub fn bm25_score(query: &str, document: &str) -> f64 {
    let q_terms: Vec<String> = tokenize(query);
    if q_terms.is_empty() {
        return 0.0;
    }
    let d_terms: Vec<String> = tokenize(document);
    if d_terms.is_empty() {
        return 0.0;
    }
    let k1 = 1.5f64;
    let b = 0.75f64;
    let avg_dl = 120.0f64;
    let dl = d_terms.len() as f64;
    let mut score = 0.0f64;

    for qt in &q_terms {
        let tf = d_terms.iter().filter(|t| *t == qt).count() as f64;
        if tf > 0.0 {
            let idf = (1.0 + (qt.len() as f64 / 4.0)).ln().max(0.5);
            let denom = tf + k1 * (1.0 - b + b * (dl / avg_dl));
            score += idf * ((tf * (k1 + 1.0)) / denom);
        }
    }
    score
}

fn tokenize(s: &str) -> Vec<String> {
    s.chars()
        .map(|c| if c.is_alphanumeric() { c.to_ascii_lowercase() } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .filter(|w| w.len() > 2)
        .map(String::from)
        .collect()
}

/// Splits UTF-8 text into overlapping chunks on paragraph/sentence boundaries
/// and returns a JSON array of strings (`["chunk1","chunk2",...]`).
/// Must be freed with `klaro_free_string`.
///
/// # Safety
/// `text` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn klaro_chunk_text_json(
    text: *const c_char,
    max_chars: usize,
    overlap_chars: usize,
) -> *mut c_char {
    if text.is_null() {
        return std::ptr::null_mut();
    }
    let input = match CStr::from_ptr(text).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let chunks = chunk_text(input, max_chars.max(120), overlap_chars);
    let json = encode_json_string_array(&chunks);
    match CString::new(json) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

pub fn chunk_text(text: &str, max_chars: usize, overlap: usize) -> Vec<String> {
    let normalized = text.replace("\r\n", "\n");
    let clean = normalized.trim();
    if clean.is_empty() {
        return Vec::new();
    }
    let chars: Vec<char> = clean.chars().collect();
    let total = chars.len();
    let mut out = Vec::new();
    let mut start = 0usize;

    while start < total {
        let mut end = (start + max_chars).min(total);
        if end < total {
            let window: String = chars[start..end].iter().collect();
            let mut best_cut: Option<usize> = None;
            for sep in ["\n\n", ". ", "? ", "! "] {
                if let Some(byte_idx) = window.rfind(sep) {
                    let char_idx = window[..byte_idx].chars().count() + 1;
                    if char_idx > max_chars / 2 {
                        best_cut = Some(best_cut.map_or(char_idx, |prev| prev.max(char_idx)));
                    }
                }
            }
            if let Some(cut) = best_cut {
                end = start + cut;
            }
        }
        let piece: String = chars[start..end].iter().collect();
        let trimmed = piece.trim();
        if !trimmed.is_empty() {
            out.push(trimmed.to_string());
        }
        if end >= total {
            break;
        }
        let next_start = end.saturating_sub(overlap);
        start = if next_start <= start { start + 1 } else { next_start };
    }
    out
}

fn encode_json_string_array(items: &[String]) -> String {
    let mut out = String::from("[");
    for (idx, item) in items.iter().enumerate() {
        if idx > 0 {
            out.push(',');
        }
        out.push('"');
        for ch in item.chars() {
            match ch {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                c if (c as u32) < 0x20 => {
                    out.push_str(&format!("\\u{:04x}", c as u32));
                }
                c => out.push(c),
            }
        }
        out.push('"');
    }
    out.push(']');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sha256_known_vector() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn test_cosine_similarity() {
        let a = [1.0f32, 0.0, 1.0];
        let b = [1.0f32, 0.0, 1.0];
        let sim = cosine_f32(&a, &b);
        assert!((sim - 1.0).abs() < 1e-6);
    }

    #[test]
    fn test_chunking_splits_and_preserves() {
        let long = (0..120)
            .map(|i| format!("Sentence {i} discusses active recall and spaced repetition."))
            .collect::<Vec<_>>()
            .join(" ");
        let chunks = chunk_text(&long, 400, 80);
        assert!(chunks.len() > 4);
        assert!(chunks.iter().all(|c| c.chars().count() <= 400));
    }

    #[test]
    fn test_bm25_orders_relevant_higher() {
        let q = "chlorophyll absorbs red blue light";
        let good = "In photosynthesis, chlorophyll absorbs mostly red and blue light inside thylakoids.";
        let bad = "Linear algebra studies vector spaces and matrices over fields.";
        assert!(bm25_score(q, good) > bm25_score(q, bad));
    }
}
