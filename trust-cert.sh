#!/usr/bin/env bash
# One-time signing setup. Creates (if needed) and trusts a stable self-signed
# code-signing identity for Snipper, so macOS keeps the Screen Recording grant
# across rebuilds (ad-hoc signatures change every build and lose the grant).
#
#   ./trust-cert.sh        # run once; macOS prompts for your login password to
#                          # add the trust setting — that's expected.
#
# The identity lives in its own throwaway keychain — your login keychain is
# untouched, and it holds nothing but this local code-signing cert.
set -euo pipefail

KC="$HOME/Library/Keychains/snipper-codesign.keychain-db"
KC_PASS="snipper-local-signing"
ID="Snipper Code Signing"

if security find-identity -v -p codesigning "$KC" 2>/dev/null | grep -q "$ID"; then
  echo "✓ '$ID' already present and trusted — nothing to do."
  exit 0
fi

if [ ! -f "$KC" ]; then
  echo "▸ Creating signing keychain…"
  security create-keychain -p "$KC_PASS" "$KC"
  security set-keychain-settings "$KC"   # no auto-lock timeout
fi
security unlock-keychain -p "$KC_PASS" "$KC"

if ! security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "$ID"; then
  echo "▸ Generating self-signed code-signing certificate…"
  cat > /tmp/snip-openssl.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = Snipper Code Signing
[ v3 ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout /tmp/snip.key -out /tmp/snip.crt -config /tmp/snip-openssl.cnf
  # Apple's `security` can't read OpenSSL 3's default PKCS#12 MAC — force legacy.
  openssl pkcs12 -export -out /tmp/snip.p12 -inkey /tmp/snip.key -in /tmp/snip.crt \
    -name "$ID" -passout pass:snipper \
    -legacy -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
  security import /tmp/snip.p12 -P snipper -k "$KC" -T /usr/bin/codesign -A
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KC" >/dev/null
  rm -f /tmp/snip.key /tmp/snip.crt /tmp/snip.p12 /tmp/snip-openssl.cnf
fi

echo "▸ Trusting the certificate for code signing — macOS will ask for your login password…"
security find-certificate -c "$ID" -p "$KC" > /tmp/snipper-cs.pem
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" /tmp/snipper-cs.pem
rm -f /tmp/snipper-cs.pem

echo "✓ Done. Now run ./build.sh — it will sign with '$ID', and the Screen"
echo "  Recording grant will persist across future rebuilds."
