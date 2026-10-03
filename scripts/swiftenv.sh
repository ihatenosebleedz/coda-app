#!/bin/sh
# Swift 6.4 toolchain, patched to run on Void.
#   - Void ships libxml2.so.16 and an unversioned-symbol libcurl; the Ubuntu
#     24.04 toolchain wants libxml2.so.2 and curl symbols versioned
#     CURL_OPENSSL_4, so we keep Ubuntu's copies in libsys/ and point both the
#     runtime loader and the linker at them.
SWIFT_ROOT="$HOME/swift-tc/swift-6.4.0-RELEASE-ubuntu24.04/usr"
SWIFT_LIBS="$HOME/swift-tc/libsys/usr/lib/x86_64-linux-gnu"

export PATH="$SWIFT_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$SWIFT_LIBS:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$SWIFT_LIBS:$LIBRARY_PATH"

exec "$@"