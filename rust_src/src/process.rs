//! Functions operating on process.

pub type LispProcessRef = ExternalPtr<Lisp_Process>;

use crate::{
    lisp::{ExternalPtr, LispObject},
    remacs_sys::{Lisp_Process, Qprocessp},
    vectors::LispVectorlikeRef,
};

impl LispObject {
    pub fn as_process(self) -> Option<LispProcessRef> {
        self.into()
    }
}

impl From<LispObject> for LispProcessRef {
    fn from(o: LispObject) -> Self {
        o.as_process().unwrap_or_else(|| wrong_type!(Qprocessp, o))
    }
}

impl From<LispObject> for Option<LispProcessRef> {
    fn from(o: LispObject) -> Self {
        o.as_vectorlike().and_then(LispVectorlikeRef::as_process)
    }
}

// use remacs_macros::lisp_fn;

// /// Return t if OBJECT is a process.
// #[lisp_fn]
// pub fn my_foo(object: LispProcessRef) {
//     let _foo = 1;
// }

// include!(concat!(env!("OUT_DIR"), "/process_exports.rs"));
