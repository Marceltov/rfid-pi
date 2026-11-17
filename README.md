# rfid-pi

Read and write RFID chips with an RC522 reader on a Raspberry Pi. An Ansible
playbook sets the Pi up; the `rfid` command does the reading and writing. It
needs nothing beyond Raspberry Pi OS and its `python3-spidev` package. Older
tutorials use SPI-Py and MFRC522-python, which are Python 2 and do not run on
current Raspberry Pi OS.

## Wiring

| RC522 | Raspberry Pi header pin |
|---|---|
| SDA | 24 (GPIO 8, CE0) |
| SCK | 23 (GPIO 11) |
| MOSI | 19 (GPIO 10) |
| MISO | 21 (GPIO 9) |
| IRQ | not connected |
| GND | 6 |
| RST | 22 (GPIO 25) |
| 3.3V | 1 (never 5 V) |

## Setting up the Pi

Flash Raspberry Pi OS Lite (Bookworm or Trixie) with Raspberry Pi Imager,
with SSH for root and your key. Put the Pi's address in `inventory.ini`, then:

```sh
ansible-playbook playbook.yml
```

It enables SPI, drives the reader's reset pin high from boot, installs
`python3-spidev` and `/usr/local/bin/rfid`, reboots if the boot config
changed, and fails unless the reader answers over SPI, which tests the wiring
without a chip. Running it again changes nothing.

## Reading and writing

On the Pi:

```sh
rfid info                              # does the reader answer?
rfid read                              # hold a chip to the reader
rfid read --dump                       # every block or page, in hex
rfid write "Hallo"                     # text
rfid write --url https://example.org   # a link a phone opens (NTAG only)
rfid write --hex 0011223344            # raw bytes
```

Every write is read back and compared. Two kinds of chip work:

- **MIFARE Classic 1K/4K** (the white card and blue fob that come with an
  RC522): data goes into the data blocks from block 8 on (`--block` to
  change it), zero-padded. The factory key `FFFFFFFFFFFF` is used unless
  `--key` says otherwise. Block 0 (the UID) and the sector trailers (the
  keys and access bits) are never written, so a chip cannot be locked by
  accident. Phones read the UID of these chips, not text.
- **NTAG213/215/216 and MIFARE Ultralight** (NFC stickers): text and URLs are
  written as an NDEF message from page 4 on, which is what a phone reads.
  The lock and configuration pages are never written.

`rfid --help` lists every option. Exit codes: 0 done, 1 error, 2 no chip
within `--timeout` seconds (default 30).

## Tests

```sh
bash tests/rfid.test.sh
```

They run without a reader: the checksum against ISO 14443-3's own examples,
the NDEF encoding, and the write paths against a simulated chip.
