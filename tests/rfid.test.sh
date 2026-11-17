#!/usr/bin/env bash
# The `rfid` command (files/rfid), without a reader: the checksum against
# the standard's own examples, the NDEF encoding, and the write paths against
# a simulated chip (block 0 and the sector trailers are never written, the
# lock pages of an NTAG neither). Run: bash tests/rfid.test.sh
cd "$(dirname "$0")/.."
exec python3 - <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("rfid", "files/rfid")
rfid = importlib.util.module_from_spec(importlib.util.spec_from_loader("rfid", loader))
loader.exec_module(rfid)

fails = 0
def check(name, got, want):
    global fails
    if got == want:
        print("ok   " + name)
    else:
        print("FAIL %s: expected [%r], got [%r]" % (name, want, got)); fails += 1
def refused(name, fn, part):
    try:
        fn(); check(name, "no error", part)
    except rfid.RfidError as e:
        check(name, part in str(e), True)

# ISO 14443-3 annex B, and HLTA as every reader sends it.
check("crc of 00 00", rfid.crc_a([0, 0]), [0xA0, 0x1E])
check("crc of 12 34", rfid.crc_a([0x12, 0x34]), [0x26, 0xCF])
check("crc of HLTA", rfid.crc_a([0x50, 0x00]), [0x57, 0xCD])
check("a wrong checksum is refused", rfid.strip_crc([0x50, 0x00, 0x57, 0xCD]), [0x50, 0x00])
refused("garbled answer", lambda: rfid.strip_crc([0x50, 0x01, 0x57, 0xCD]), "garbled")

check("trailers of a 1K card", [b for b in range(64) if rfid.is_trailer(b)], list(range(3, 64, 4)))
check("trailers in a 4K card's big sectors", [b for b in range(128, 176) if rfid.is_trailer(b)], [143, 159, 175])
check("data blocks from 8", rfid.classic_data_blocks(8, 20), [8, 9, 10, 12, 13, 14, 16, 17, 18])
check("block 0 is never a data block", rfid.classic_data_blocks(0, 8), [1, 2, 4, 5, 6])

check("url record", rfid.ndef_uri("https://example.org").hex(), "d1010c5504" + b"example.org".hex())
check("the longest prefix wins", rfid.ndef_uri("https://www.example.org")[4], 2)
check("url round trip", rfid.ndef_parse(rfid.ndef_tlv(rfid.ndef_uri("https://example.org/a?b=c"))), ("url", "https://example.org/a?b=c"))
check("text round trip", rfid.ndef_parse(b"\0\0" + rfid.ndef_tlv(rfid.ndef_text("Grüße"))), ("text", "Grüße"))
long = "x" * 400
check("long text round trip", rfid.ndef_parse(rfid.ndef_tlv(rfid.ndef_text(long))), ("text", long))
check("a TLV before the message is skipped", rfid.ndef_parse(b"\x01\x03\xa0\x0c\x34" + rfid.ndef_tlv(rfid.ndef_uri("tel:123"))), ("url", "tel:123"))
check("empty memory has no message", rfid.ndef_parse(bytes(144)), None)
check("a cut-off message does not crash", rfid.ndef_parse(b"\x03\x10\xd1\x01"), None)

class FakeReader:
    """A chip's memory behind the Reader methods the chip classes call."""
    def __init__(self, cells, size, key=None, locked=()):
        self.mem = [[0] * size for _ in range(cells)]
        self.size, self.key, self.locked, self.writes, self.authed = size, key, locked, [], None
    def classic_auth(self, block, key, uid):
        ok = key == self.key and rfid.sector_start(block) not in self.locked
        self.authed = rfid.sector_start(block) if ok else None
        return ok
    def must_select(self): self.authed = None
    def read16(self, a):
        if self.size == 16:
            assert self.authed == rfid.sector_start(a), "read without authentication"
            return list(self.mem[a])
        return sum((self.mem[(a + i) % len(self.mem)] for i in range(4)), [])
    def classic_write(self, block, data):
        assert self.authed == rfid.sector_start(block), "write without authentication"
        self.writes.append(block); self.mem[block] = list(data)
    def ultralight_write(self, page, data):
        assert len(data) == 4
        self.writes.append(page); self.mem[page] = list(data)
    def ultralight_version(self): return [0, 4, 4, 2, 1, 0, 0x0F, 3]

KEY = [0xFF] * 6
def classic(**kw):
    r = FakeReader(64, 16, key=KEY, **kw)
    return r, rfid.Classic(r, [1, 2, 3, 4], 0x08, KEY)

r, c = classic()
check("40 bytes land in three blocks", c.write(8, b"a" * 40), "blocks 8-10")
check("the rest is zero-padded", bytes(r.mem[10]), b"a" * 8 + bytes(8))
check("and reads back as text", c.read_text(8), b"a" * 40)
r, c = classic()
c.write(8, b"b" * 16 * 7)
check("a long write skips the trailers", r.writes, [8, 9, 10, 12, 13, 14, 16])
check("exactly full blocks read back whole", c.read_text(8), b"b" * 112)
refused("block 0", lambda: classic()[1].write(0, b"x"), "not a data block")
refused("a trailer", lambda: classic()[1].write(11, b"x"), "not a data block")
refused("past the end", lambda: classic()[1].write(64, b"x"), "not a data block")
refused("too much", lambda: classic()[1].write(60, b"x" * 49), "do not fit")
r, c = classic(locked=[12])
refused("a sector with another key", lambda: c.write(8, b"c" * 64), "key does not open block 12")
check("nothing was written into it", r.writes, [8, 9, 10])
check("a locked sector shows in the dump", sum("locked" in l for l in c.dump()), 4)
r, c = classic()
r.classic_write = lambda block, data: None
r.authed = 8
refused("a write that did not take", lambda: c.write(8, b"x"), "reads back differently")

def ntag():
    r = FakeReader(45, 4)
    return r, rfid.Ultralight(r)
r, n = ntag()
check("an NTAG213 is recognised", n.name, "NTAG213, 144 bytes")
msg = rfid.ndef_tlv(rfid.ndef_uri("https://example.org"))
check("a url lands from page 4", n.write(4, msg), "pages 4-8")
check("and is read back as one", rfid.ndef_parse(n.user_memory()), ("url", "https://example.org"))
check("144 bytes fit", ntag()[1].write(4, bytes(144)), "pages 4-39")
refused("145 bytes", lambda: ntag()[1].write(4, bytes(145)), "do not fit")
refused("the lock pages", lambda: ntag()[1].write(40, bytes(4)), "not a user page")
refused("the header pages", lambda: ntag()[1].write(2, bytes(4)), "not a user page")

print("all ok" if not fails else "%d failed" % fails)
sys.exit(1 if fails else 0)
PY
