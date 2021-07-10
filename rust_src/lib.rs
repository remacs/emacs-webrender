use std::{os::raw::c_char, thread};

extern "C" {
    pub fn emacs_main(argc: i32, argv: *mut *mut c_char) -> i32;
}

#[no_mangle]
pub extern "C" fn main(argc: i32, argv: *mut *mut c_char) -> i32 {
    let current_thread = thread::current();

    // make argv sendable to thread
    let argv: usize = argv as usize;

    // Spawning emacs_main in another thread isn't neceassary to make it run.
    // Just show that we can do this.
    thread::spawn(move || {
        unsafe { emacs_main(argc, argv as *mut *mut c_char) };
        current_thread.unpark();
    });

    thread::park();
    return 1;
}

// Include the main c_exports file that holds the main rust_init_syms.
// This function calls the other crates init_syms functions which contain
// the generated bindings.
#[cfg(not(test))]
include!(concat!(env!("OUT_DIR"), "/c_exports.rs"));
