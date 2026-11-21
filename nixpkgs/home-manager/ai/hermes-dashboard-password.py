"""Hermes dashboard password hash, the format of plugins/dashboard_auth/basic (scrypt$n$r$p$salt$dk).

  hash:    password on stdin -> new hash on stdout
  verify:  password on stdin, hash in $OLD -> exit 0 when it matches
Standalone so activation doesn't depend on Hermes' (mutable) install.
"""
import base64, hashlib, hmac, os, secrets, sys

N, R, P, DKLEN, SALT = 2**14, 8, 1, 32, 16
pw = sys.stdin.read().encode("utf-8")
if sys.argv[1:] == ["hash"]:
    salt = secrets.token_bytes(SALT)
    dk = hashlib.scrypt(pw, salt=salt, n=N, r=R, p=P, dklen=DKLEN, maxmem=0)
    print(f"scrypt${N}${R}${P}${base64.b64encode(salt).decode()}${base64.b64encode(dk).decode()}")
elif sys.argv[1:] == ["verify"]:
    try:
        scheme, n, r, p, salt, dk = os.environ["OLD"].split("$")
        want = base64.b64decode(dk)
        ok = scheme == "scrypt" and hmac.compare_digest(
            hashlib.scrypt(pw, salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p), dklen=len(want), maxmem=0), want)
    except (KeyError, ValueError, TypeError, MemoryError):
        ok = False
    sys.exit(0 if ok else 1)
else:
    sys.exit("usage: hash | verify")
