#![allow(non_upper_case_globals)]
#![allow(non_snake_case)]
#![cfg_attr(feature = "strict", deny(warnings))]

#[macro_use]
extern crate lazy_static;

mod docfile;

pub use crate::{
    // Used by make-docfile
    docfile::scan_rust_file,
};
