#!/bin/sh
set -eu
bad=$(git ls-files | grep -E '\.(store|sqlite|dmg|p12|cer|mobileprovision|pem)$' || true)
if [ -n "$bad" ]; then echo "Forbidden user/release/credential artifacts:"; echo "$bad"; exit 1; fi
if git grep -nEI '(sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._-]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)' -- ':!Scripts/check-repository-safety.sh' ':!Tests/**'; then
  echo "Possible API key or private key found."; exit 1
fi
