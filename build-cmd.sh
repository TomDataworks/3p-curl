#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

CURL_VERSION="7.50.0"
CURL_SOURCE_DIR="curl"

# load autbuild provided shell functions and variables
eval "$("$AUTOBUILD" source_environment)"

top="$(pwd)"
stage="$(pwd)/stage"

ZLIB_INCLUDE="${stage}"/packages/include/zlib
OPENSSL_INCLUDE="${stage}"/packages/include/openssl

[ -f "$ZLIB_INCLUDE"/zlib.h ] || fail "You haven't installed the zlib package yet."
[ -f "$OPENSSL_INCLUDE"/ssl.h ] || fail "You haven't installed the openssl package yet."

echo "${CURL_VERSION}" > "${stage}/VERSION.txt"

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/{debug,release}/lib*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}

# See if there's anything wrong with the checked out or
# generated files.  Main test is to confirm that c-ares
# is defeated and we're using a threaded resolver.
check_damage ()
{
    case "$1" in
        "windows")
            echo "Verifying Ares is disabled"
            grep 'USE_ARES\s*1' lib/config-win32.h | grep '^/\*'
        ;;

        "darwin")
            echo "Verifying Ares is disabled"
            egrep 'USE_THREADS_POSIX[[:space:]]+1' lib/curl_config.h
        ;;

        "linux")
            echo "Verifying Ares is disabled"
            egrep 'USE_THREADS_POSIX[[:space:]]+1' lib/curl_config.h
        ;;
    esac
}

pushd "$CURL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            check_damage "$AUTOBUILD_PLATFORM"
            packages="$(cygpath -m "$stage/packages")"
            load_vsvars
            pushd lib

                # Debug target.  DLL for SSL, static archives
                # for libcurl and zlib.  (Config created by Linden Lab)
                nmake /f Makefile.vc14 CFG=debug-ssl-dll-zlib \
                    OPENSSL_PATH="$packages/include/openssl" \
                    ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlibd.lib" MACHINE=x86 USE_IDN=yes \
                    INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                    LIB="$LIB;$packages/lib/debug" \
                    LINDEN_INCPATH="$packages/include" \
                    LINDEN_LIBPATH="$packages/lib/debug"

                # Release target.  DLL for SSL, static archives
                # for libcurl and zlib.  (Config created by Linden Lab)
                nmake /f Makefile.vc14 CFG=release-ssl-dll-zlib \
                    OPENSSL_PATH="$packages/include/openssl" \
                    ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlib.lib" MACHINE=x86 USE_IDN=yes \
                    INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                    LIB="$LIB;$packages/lib/release" \
                    LINDEN_INCPATH="$packages/include" \
                    LINDEN_LIBPATH="$packages/lib/release" 

            popd

            pushd src
                # Real unit tests aren't running on Windows yet.  But
                # we can at least build the curl command itself and
                # invoke and inspect it a bit.

                # Target can be 'debug' or 'release' but CFG's
                # are always 'release-*' for the executable build.

                nmake /f Makefile.vc14 debug CFG=release-ssl-dll-zlib MACHINE=x86 USE_IDN=yes \
                    OPENSSL_PATH="$packages/include/openssl" \
                    ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlibd.lib" \
                    INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                    LIB="$LIB;$packages/lib/debug" \
                    LINDEN_INCPATH="$packages/include" \
                    LINDEN_LIBPATH="$packages/lib/debug" 
            popd

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                # Nothin' to do yet

                popd
            fi

            # Stage archives
            mkdir -p "${stage}"/lib/{debug,release}
            cp -a lib/debug-ssl-dll-zlib/libcurld.lib "${stage}"/lib/debug/libcurld.lib
            cp -a lib/release-ssl-dll-zlib/libcurl.lib "${stage}"/lib/release/libcurl.lib

            # Stage curl.exe and provide .dll's it needs
            mkdir -p "${stage}"/bin
            cp -af "${stage}"/packages/lib/debug/*.{dll,pdb} "${stage}"/bin/
            chmod +x-w "${stage}"/bin/*.dll   # correct package permissions
            cp -a src/curl.{exe,ilk,pdb} "${stage}"/bin/

            # Stage headers
            mkdir -p "${stage}"/include
            cp -a include/curl/ "${stage}"/include/

            # Run 'curl' as a sanity check
            echo "======================================================="
            echo "==    Verify expected versions of libraries below    =="
            echo "======================================================="
            "${stage}"/bin/curl.exe --version
            echo "======================================================="
            echo "======================================================="

            # Clean
            pushd lib
                nmake /f Makefile.vc14 clean
            popd
            pushd src
                nmake /f Makefile.vc14 clean
            popd
        ;;

        "windows64")
            check_damage "$AUTOBUILD_PLATFORM"
            packages="$(cygpath -m "$stage/packages")"
            load_vsvars
            pushd lib

                # Debug target.  DLL for SSL, static archives
                # for libcurl and zlib.  (Config created by Linden Lab)
                nmake /f Makefile.vc14 CFG=debug-ssl-dll-zlib MACHINE=x64 USE_IDN=yes \
                    OPENSSL_PATH="$packages/include/openssl" \
                    ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlibd.lib" \
                    INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                    LIB="$LIB;$packages/lib/debug" \
                    LINDEN_INCPATH="$packages/include" \
                    LINDEN_LIBPATH="$packages/lib/debug"

                # Release target.  DLL for SSL, static archives
                # for libcurl and zlib.  (Config created by Linden Lab)
                nmake /f Makefile.vc14 CFG=release-ssl-dll-zlib MACHINE=x64 USE_IDN=yes \
                    OPENSSL_PATH="$packages/include/openssl" \
                    ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlib.lib" \
                    INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                    LIB="$LIB;$packages/lib/release" \
                    LINDEN_INCPATH="$packages/include" \
                    LINDEN_LIBPATH="$packages/lib/release" 

            popd

            pushd src
                # Real unit tests aren't running on Windows yet.  But
                # we can at least build the curl command itself and
                # invoke and inspect it a bit.

                # Target can be 'debug' or 'release' but CFG's
                # are always 'release-*' for the executable build.

                nmake /f Makefile.vc14 debug CFG=release-ssl-dll-zlib MACHINE=x64 USE_IDN=yes \
                    OPENSSL_PATH="$packages/include/openssl" \
                    ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlibd.lib" \
                    INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                    LIB="$LIB;$packages/lib/debug" \
                    LINDEN_INCPATH="$packages/include" \
                    LINDEN_LIBPATH="$packages/lib/debug" 
            popd

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                # Nothin' to do yet

                popd
            fi

            # Stage archives
            mkdir -p "${stage}"/lib/{debug,release}
            cp -a lib/debug-ssl-dll-zlib/libcurld.lib "${stage}"/lib/debug/libcurld.lib
            cp -a lib/release-ssl-dll-zlib/libcurl.lib "${stage}"/lib/release/libcurl.lib

            # Stage curl.exe and provide .dll's it needs
            mkdir -p "${stage}"/bin
            cp -af "${stage}"/packages/lib/debug/*.{dll,pdb} "${stage}"/bin/
            chmod +x-w "${stage}"/bin/*.dll   # correct package permissions
            cp -a src/curl.{exe,ilk,pdb} "${stage}"/bin/

            # Stage headers
            mkdir -p "${stage}"/include
            cp -a include/curl/ "${stage}"/include/

            # Run 'curl' as a sanity check
            echo "======================================================="
            echo "==    Verify expected versions of libraries below    =="
            echo "======================================================="
            "${stage}"/bin/curl.exe --version
            echo "======================================================="
            echo "======================================================="

            # Clean
            pushd lib
                nmake /f Makefile.vc14 clean
            popd
            pushd src
                nmake /f Makefile.vc14 clean
            popd
        ;;

        "darwin")
            DEVELOPER="$(xcode-select -print-path)"
            sdk="${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.11.sdk" 
            opts="${TARGET_OPTS:--arch x86_64 -iwithsysroot $sdk -mmacosx-version-min=10.8}"

            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/lib/debug"
            rm -rf Resources/ ../Resources tests/Resources/

            # Debug configure and build

            # Curl configure has trouble finding zlib 'framework' that
            # it doesn't have with openssl.  We help it with CPPFLAGS.

            # -g/-O options controled by --enable-debug/-optimize.  Unfortunately,
            # --enable-debug also defines DEBUGBUILD which changes behaviors.
            CFLAGS="$opts -gdwarf-2 -O0" \
                CXXFLAGS="$opts -gdwarf-2 -O0" \
                LDFLAGS=-L"$stage"/packages/lib/debug \
                CPPFLAGS="$opts -I$stage/packages/include/zlib" \
                ./configure  --disable-ldap --disable-ldaps --enable-shared=no \
                --disable-debug --disable-curldebug --disable-optimize \
                --prefix="$stage" --libdir="${stage}"/lib/debug --enable-threaded-resolver \
                --with-ssl="${stage}/packages" --with-zlib="${stage}/packages" --with-libidn="${stage}/packages" --without-libssh2
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install

            # conditionally run unit tests
            # Disabled here and below by default on Mac because they
            # trigger the Mac firewall dialog and that may make
            # automated builds unreliable.  During development,
            # explicitly inhibit the disable and run the tests.  They
            # matter.
            if [ "${DISABLE_UNIT_TESTS:-1}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 906.  It fails in the
                    # 7.33 distribution with our configuration options.  530 fails
                    # in TeamCity.  (Expect problems with the unit tests, they're
                    # very sensitive to environment.)
                    make quiet-test TEST_Q='-n !906 !530 !564 !584 !706 !1316'
                popd
            fi

            make distclean 

            CFLAGS="$opts -gdwarf-2" \
                CXXFLAGS="$opts -gdwarf-2" \
                LDFLAGS=-L"$stage"/packages/lib/release \
                CPPFLAGS="$opts -I$stage/packages/include/zlib" \
                ./configure  --disable-ldap --disable-ldaps --enable-shared=no \
                --disable-debug --disable-curldebug --enable-optimize \
                --prefix="$stage" --libdir="${stage}"/lib/release --enable-threaded-resolver \
                --with-ssl="${stage}/packages" --with-zlib="${stage}/packages" --with-libidn="${stage}packages" --without-libssh2
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-1}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 906.  It fails in the
                    # 7.33 distribution with our configuration options.  530 fails
                    # in TeamCity.  (Expect problems with the unit tests, they're
                    # very sensitive to environment.)
                    make quiet-test TEST_Q='-n !906 !530 !564 !584 !706 !1316'
                popd
            fi

            make distclean 
        ;;

        "linux")
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Default target to 32-bit
            opts="${TARGET_OPTS:--m32}"
            JOBS=`cat /proc/cpuinfo | grep processor | wc -l`
            HARDENED="-fstack-protector"
            HARDENED_CPPFLAGS="-D_FORTIFY_SOURCE=2"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS" 
            fi

            # Force static linkage to libz and openssl by moving .sos out of the way
            trap restore_sos EXIT
            for solib in "${stage}"/packages/lib/{debug,release}/lib{z,ssl,crypto}.so*; do
                if [ -f "$solib" ]; then
                    mv -f "$solib" "$solib".disable
                fi
            done
            
            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/lib/debug"

            # Autoconf's configure will do some odd things to flags.  '-I' options
            # will get transferred to '-isystem' and there's a problem with quoting.
            # Linking and running also require LD_LIBRARY_PATH to locate the OpenSSL
            # .so's.  The '--with-ssl' option could do this if we had a more normal
            # package layout.
            #
            # configure-time compilation looks like:
            # ac_compile='$CC -c $CFLAGS $CPPFLAGS conftest.$ac_ext >&5'
            # ac_link='$CC -o conftest$ac_exeext $CFLAGS $CPPFLAGS $LDFLAGS conftest.$ac_ext $LIBS >&5'
            saved_path="$LD_LIBRARY_PATH"

            # Debug configure and build
            export LD_LIBRARY_PATH="${stage}"/packages/lib/debug:"$saved_path"

            # -g/-O options controled by --enable-debug/-optimize.  Unfortunately,
            # --enable-debug also defines DEBUGBUILD which changes behaviors.
            CFLAGS="$opts" \
                CXXFLAGS="$opts" \
                CPPFLAGS="${CPPFLAGS} $opts -I$stage/packages/include/idn -I$stage/packages/include/zlib" \
                LIBS="-ldl" \
                LDFLAGS="-L$stage/packages/lib/debug/" \
                ./configure --disable-ldap --disable-ldaps --enable-shared=no --enable-threaded-resolver \
                --without-libssh2 --disable-debug --disable-curldebug --disable-optimize \
                --prefix="$stage" --libdir="$stage"/lib/debug \
                --with-ssl="$stage"/packages/ --with-zlib="$stage"/packages/ --with-libidn="$stage"/packages/
            check_damage "$AUTOBUILD_PLATFORM"
            make -j$JOBS
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 320.  It fails in the
                    # 7.41 distribution with our configuration options.
                    #
                    # Expect problems with the unit tests, they're very sensitive
                    # to environment.
                    make quiet-test TEST_Q='-n !320'
                popd
            fi

            make distclean 

            # Release configure and build
            export LD_LIBRARY_PATH="${stage}"/packages/lib/release:"$saved_path"

            CFLAGS="$opts $HARDENED" \
                CXXFLAGS="$opts $HARDENED"  \
                CPPFLAGS="${CPPFLAGS} $opts $HARDENED_CPPFLAGS -I$stage/packages/include/idn -I$stage/packages/include/zlib" \
                LIBS="-ldl" \
                LDFLAGS="-L$stage/packages/lib/release" \
                ./configure --disable-ldap --disable-ldaps --enable-shared=no --enable-threaded-resolver \
                --without-libssh2 --disable-debug --disable-curldebug --enable-optimize \
                --prefix="$stage" --libdir="$stage"/lib/release \
                --with-ssl="$stage"/packages --with-zlib="$stage"/packages --with-libidn="$stage"/packages                 
            check_damage "$AUTOBUILD_PLATFORM"
            make -j$JOBS
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 320.  It fails in the
                    # 7.41 distribution with our configuration options.
                    #
                    # Expect problems with the unit tests, they're very sensitive
                    # to environment.
                    make quiet-test TEST_Q='-n !320'
                popd
            fi

            make distclean 

            export LD_LIBRARY_PATH="$saved_path"
        ;;
        "linux64")
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Default target to 64-bit
            opts="${TARGET_OPTS:--m64}"
            JOBS=`cat /proc/cpuinfo | grep processor | wc -l`
            HARDENED="-fstack-protector"
            HARDENED_CPPFLAGS="-D_FORTIFY_SOURCE=2"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS" 
            fi

            # Force static linkage to libz and openssl by moving .sos out of the way
            trap restore_sos EXIT
            for solib in "${stage}"/packages/lib/{debug,release}/lib{z,ssl,crypto}.so*; do
                if [ -f "$solib" ]; then
                    mv -f "$solib" "$solib".disable
                fi
            done
            
            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/lib/debug"
            
            # Autoconf's configure will do some odd things to flags.  '-I' options
            # will get transferred to '-isystem' and there's a problem with quoting.
            # Linking and running also require LD_LIBRARY_PATH to locate the OpenSSL
            # .so's.  The '--with-ssl' option could do this if we had a more normal
            # package layout.
            #
            # configure-time compilation looks like:
            # ac_compile='$CC -c $CFLAGS $CPPFLAGS conftest.$ac_ext >&5'
            # ac_link='$CC -o conftest$ac_exeext $CFLAGS $CPPFLAGS $LDFLAGS conftest.$ac_ext $LIBS >&5'
            saved_path="$LD_LIBRARY_PATH"

            # Debug configure and build
            export LD_LIBRARY_PATH="${stage}"/packages/lib/debug:"$saved_path"

            # -g/-O options controled by --enable-debug/-optimize.  Unfortunately,
            # --enable-debug also defines DEBUGBUILD which changes behaviors.
            CFLAGS="$opts" \
                CXXFLAGS="$opts" \
                CPPFLAGS="${CPPFLAGS} $opts -I$stage/packages/include/idn -I$stage/packages/include/zlib" \
                LIBS="-ldl" \
                LDFLAGS="-L$stage/packages/lib/debug/" \
                ./configure --disable-ldap --disable-ldaps --enable-shared=no --enable-threaded-resolver \
                --without-libssh2 --disable-debug --disable-curldebug --disable-optimize \
                --prefix="$stage" --libdir="$stage"/lib/debug \
                --with-ssl="$stage"/packages/ --with-zlib="$stage"/packages/ --with-libidn="$stage"/packages
            check_damage "$AUTOBUILD_PLATFORM"
            make -j$JOBS
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 320.  It fails in the
                    # 7.41 distribution with our configuration options.
                    #
                    # Expect problems with the unit tests, they're very sensitive
                    # to environment.
                    make quiet-test TEST_Q='-n !320'
                popd
            fi

            make distclean 

            # Release configure and build
            export LD_LIBRARY_PATH="${stage}"/packages/lib/release:"$saved_path"

            CFLAGS="$opts $HARDENED" \
                CXXFLAGS="$opts $HARDENED"  \
                CPPFLAGS="${CPPFLAGS} $opts $HARDENED_CPPFLAGS -I$stage/packages/include/idn -I$stage/packages/include/zlib" \
                LIBS="-ldl" \
                LDFLAGS="-L$stage/packages/lib/release" \
                ./configure --disable-ldap --disable-ldaps --enable-shared=no --enable-threaded-resolver \
                --without-libssh2 --disable-debug --disable-curldebug --enable-optimize \
                --prefix="$stage" --libdir="$stage"/lib/release \
                --with-ssl="$stage"/packages --with-zlib="$stage"/packages --with-libidn="$stage"/packages
            check_damage "$AUTOBUILD_PLATFORM"
            make -j$JOBS
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 320.  It fails in the
                    # 7.41 distribution with our configuration options.
                    #
                    # Expect problems with the unit tests, they're very sensitive
                    # to environment.
                    make quiet-test TEST_Q='-n !320'
                popd
            fi

            make distclean 

            export LD_LIBRARY_PATH="$saved_path"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/curl.txt"
popd

mkdir -p "$stage"/docs/curl/
cp -a "$top"/README.Linden "$stage"/docs/curl/

pass

