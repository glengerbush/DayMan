#!/usr/bin/env bash
set -euo pipefail

output_path=${1:-dayman-android-signing.tar.gz}
working_dir=$(mktemp -d)

if [[ -e "$output_path" ]]; then
  echo "error: refusing to overwrite existing signing bundle: $output_path" >&2
  exit 1
fi

cleanup() {
  rm -rf -- "$working_dir"
}
trap cleanup EXIT

openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:4096 \
  -out "$working_dir/private-key.pem"
openssl req \
  -new \
  -x509 \
  -key "$working_dir/private-key.pem" \
  -out "$working_dir/certificate.pem" \
  -days 36500 \
  -subj "/CN=DayMan Android Release/O=DayMan/"
openssl pkcs8 \
  -topk8 \
  -nocrypt \
  -inform PEM \
  -outform DER \
  -in "$working_dir/private-key.pem" \
  -out "$working_dir/private-key.pk8"

tar -C "$working_dir" \
  -czf "$output_path" \
  private-key.pk8 \
  certificate.pem
chmod 600 "$output_path"

echo "Created $output_path"
echo "Keep this file private and backed up; future APK updates must use the same key."
