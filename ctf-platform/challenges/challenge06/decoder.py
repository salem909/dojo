#!/usr/bin/env python3
import base64
import sys

KEY = 23


def decode(data: bytes) -> bytes:
    raw = base64.b64decode(data)
    return bytes([b ^ KEY for b in raw])


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: decoder.py <file>")
        return 1
    content = open(sys.argv[1], "rb").read().strip()
    print(decode(content).decode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
