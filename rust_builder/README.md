# rust_lib_yangi_alifbo

Not a package to use on its own: it only builds the Rust crate in `../rust` with
[cargokit](https://github.com/irondash/cargokit) and bundles the library with the Yangi alifbo app on Android, iOS,
macOS, Windows and Linux. The app calls it through the bindings in `../lib/src/rust`.
