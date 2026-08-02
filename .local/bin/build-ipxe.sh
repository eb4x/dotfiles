#!/usr/bin/env bash
set -euo pipefail

# Builds the iPXE binaries that setup-dnsmasq-ipxe.sh installs, and rewrites the
# vendored copies under .local/share/ipxe/blobs/.
#
# Deliberately NOT called from setup-dnsmasq-ipxe.sh. The point of vendoring is
# that the bytes change only when someone decides they should; this script is
# that decision, made on purpose and committed as a reviewable diff.
#
# Why we build at all, rather than downloading from boot.ipxe.org: that host
# serves rolling builds of git master with no version, no checksum, no signature
# and no immutable URL, so a pinned hash is stale within hours (measured
# 2026-08-02: all three artifacts changed inside a 40-minute window). The distro
# packages do not rescue it either -- AlmaLinux 10's ipxe-bootimgs-x86 ships
# neither ipxe-x86_64.efi nor ipxe-i386.efi, and Alma 8's build predates HTTPS
# support -- so the same script would deploy a different iPXE per host.
#
# iPXE is byte-reproducible if three things are held still: the source commit,
# SOURCE_DATE_EPOCH (Makefile.housekeeping otherwise stamps `date +%s` into
# _build_timestamp) and the toolchain. The first two are pinned here; the third
# is not pinnable from a shell script, so build.env records it and a future byte
# mismatch can be explained rather than guessed at.

ipxe_commit=12798ec29aa8a64d8675c4378b99f5fe28447afb  # v2.0.0, 2026-03-06
ipxe_src=${IPXE_SRC:-~/src/ipxe}

# Resolve blobs/ relative to this script so it works both from the ~/src/dotfiles
# working clone and from the $HOME worktree of the bare repo.
blobs=$(dirname "$(readlink -f "$0")")/../share/ipxe/blobs

# Mozilla's root CA store, vendored so the build needs no network and every
# build host produces identical bytes (the system ca-certificates package
# differs per host and per update date, which would break reproducibility).
# Refresh from https://curl.se/docs/caextract.html -- it publishes dated,
# immutable cacert-YYYY-MM-DD.pem files each with a .sha256 alongside, which is
# exactly what boot.ipxe.org does not offer.
ca_bundle=$blobs/cacert-2026-07-16.pem

# syslinux/mtools/xorriso/edk2-tools are only needed for the .iso/.usb/.dsk and
# ROM targets, which we do not build.
sudo dnf install -y git gcc binutils make xz-devel \
  perl-interpreter perl-Getopt-Long perl-FindBin perl-lib

if [ ! -d "$ipxe_src/.git" ]; then
  git clone https://github.com/ipxe/ipxe.git "$ipxe_src"
fi
git -C "$ipxe_src" fetch --tags origin
git -C "$ipxe_src" checkout --detach "$ipxe_commit"

# A stale object tree is the likeliest reason two builds of the same commit
# disagree; config changes in particular only reach version.o via a rebuild.
git -C "$ipxe_src" clean -xfd src

# config/local/ is git-ignored upstream (it ships only a .gitignore) and each
# config/<name>.h includes its local/ counterpart LAST, so defines here win over
# everything above them. This is the same mechanism Fedora's
# 0001-build-customize-configuration.patch uses.
cat > "$ipxe_src/src/config/local/general.h" << 'EOF'
/* Not redundant: config/general.h enables HTTPS by default but then does
 *
 *   #if defined ( PLATFORM_pcbios )
 *     #undef DOWNLOAD_PROTO_HTTPS
 *
 * so a stock undionly.kpxe has no HTTPS at all and cannot fetch the https://
 * mirror URLs our boot menus use. This re-enables it for every platform.
 */
#define DOWNLOAD_PROTO_HTTPS
EOF

cat > "$ipxe_src/src/config/local/crypto.h" << 'EOF'
/* Stock iPXE reaches out over PLAIN HTTP during certificate validation: it
 * fetches cross-signed certificates from CROSSCERT (http://ca.ipxe.org/auto) to
 * repair an incomplete chain, and OCSP responders are plain http by protocol
 * design. We do not allow external plain-http fetches, so both are off.
 *
 * The trade-off, recorded so it is not rediscovered the hard way: a mirror that
 * serves an incomplete chain now fails validation instead of being silently
 * repaired, and revoked certificates are not detected. Both are acceptable when
 * we choose the mirrors and pin their roots ourselves.
 *
 * CROSSCERT must be redefined EMPTY, not undefined: net/validator.c uses it
 * unconditionally (`static const char crosscert_default[] = CROSSCERT;`) so
 * #undef alone fails to compile. The empty string is the sanctioned off switch --
 * validator.c bails on `if ( ! crosscert[0] )`. OCSP_CHECK is #ifdef-guarded in
 * include/ipxe/ocsp.h, so plain #undef is right for that one.
 */
#undef CROSSCERT
#define CROSSCERT ""
#undef OCSP_CHECK
EOF

# Root certificates must be baked in. Handing them over DHCP (the "trust"
# setting, option 175 sub-option 90) looks like it works -- `show trust` even
# prints them -- but does not: crypto/rootcert.c reads that setting from
# rootcert_init(), a STARTUP_LATE function that latches `initialised = 1` on
# first run, which happens before any DHCP lease exists. Measured on a real PXE
# boot, a DEBUG=rootcert build reports "ROOTCERT using 1 built-in
# certificate(s)" -- the iPXE CA -- no matter what DHCP sends afterwards.
#
# Both variables are needed, and they do different jobs:
#   TRUST= registers each certificate's sha256 fingerprint as a trust anchor.
#   CERT=  embeds the certificate itself, so x509_auto_append() can complete a
#          chain whose root the server does not send.
# TRUST= alone is not enough. Neither of our mirrors sends a self-signed root:
# mirror.accum.se terminates in an ISRG "Root YR" cross-signed by ISRG Root X1,
# and almalinux.uib.no in a HARICA 2021 cross-signed by HARICA RootCA 2015. Only
# the issuers are in Mozilla's store, so iPXE needs the actual certs to bridge.
#
# CERT= takes the bundle as-is: Makefile.housekeeping cats its inputs and
# csplits them itself, "even if original files contained certificate chains".
#
# TRUST= cannot. It is a foreach over comma-separated paths running
#   openssl x509 -in <file> -noout -sha256 -fingerprint
# and that reads only the FIRST certificate in a file, so handing it the bundle
# would silently trust exactly one root. Hence one file per certificate, but
# only for TRUST=.
#
# Split with openssl rather than by slicing on BEGIN/END: the bundle carries a
# descriptive header plus a name and separator line above every certificate, so
# a text split yields chunks that are not certificates. Round-tripping through
# PKCS#7 re-emits canonical PEM and fails here, loudly, on a malformed bundle.
# sed keeps only BEGIN..END lines (dropping the subject=/issuer= annotations
# -print_certs adds); awk starts a new file at each BEGIN.
certs=$(mktemp -d)
trap 'rm -rf "$certs"' EXIT
openssl crl2pkcs7 -nocrl -certfile "$ca_bundle" \
  | openssl pkcs7 -print_certs \
  | sed -n '/^-----BEGIN CERTIFICATE-----$/,/^-----END CERTIFICATE-----$/p' \
  | awk -v d="$certs" '/^-----BEGIN CERTIFICATE-----$/ { n++ }
                       n { print > sprintf ( "%s/c%04d.pem", d, n ) }'

# A silent shortfall would quietly narrow the trust store rather than fail.
want=$(grep -c '^-----BEGIN CERTIFICATE-----$' "$ca_bundle")
got=$(find "$certs" -name 'c*.pem' | wc -l)
if [ "$want" -ne "$got" ]; then
  echo "ERROR: split $got certificates out of $ca_bundle, expected $want" >&2
  exit 1
fi

trust_list=$(find "$certs" -name 'c*.pem' | sort | paste -sd,)
echo "Embedding and trusting $got root certificates from $(basename "$ca_bundle")"

# The commit's own author date is the one epoch that is both stable and
# meaningful; `date +%s` here would make every rebuild differ, which is exactly
# the property we are trying to remove.
SOURCE_DATE_EPOCH=$(git -C "$ipxe_src" show -s --format=%ct HEAD)
export SOURCE_DATE_EPOCH

# NO_WERROR=1 matches Fedora's spec; iPXE does not build clean against current gcc.
make -C "$ipxe_src/src" -j"$(nproc)" NO_WERROR=1 \
  CERT="$ca_bundle" TRUST="$trust_list" \
  bin/undionly.kpxe bin-x86_64-efi/ipxe.efi bin-i386-efi/ipxe.efi

install -d "$blobs"
install -m 0644 "$ipxe_src/src/bin/undionly.kpxe"       "$blobs/undionly.kpxe"
install -m 0644 "$ipxe_src/src/bin-x86_64-efi/ipxe.efi" "$blobs/ipxe.efi"
install -m 0644 "$ipxe_src/src/bin-i386-efi/ipxe.efi"   "$blobs/ipxe-i386.efi"

# sha256sums is redundant with git's own content addressing; it is here because a
# blob refresh shows up in `git log -p` as "Binary files differ" and nothing
# else, and because it catches a truncated or partial checkout at deploy time.
(cd "$blobs" && sha256sum undionly.kpxe ipxe.efi ipxe-i386.efi \
   "$(basename "$ca_bundle")" > sha256sums)

cat > "$blobs/build.env" << EOF
ipxe_commit=$ipxe_commit
ipxe_describe=$(git -C "$ipxe_src" describe --tags --always HEAD)
source_date_epoch=$SOURCE_DATE_EPOCH
ca_bundle=$(basename "$ca_bundle")
ca_bundle_roots=$(grep -c 'BEGIN CERTIFICATE' "$ca_bundle")
gcc=$(rpm -q --qf '%{version}-%{release}' gcc)
binutils=$(rpm -q --qf '%{version}-%{release}' binutils)
EOF

echo
echo "Vendored blobs updated. Review and commit:"
cat "$blobs/sha256sums" "$blobs/build.env"
