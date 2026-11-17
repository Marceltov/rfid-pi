# CLAUDE.md

An Ansible playbook and a Python command (`files/rfid`) to read and write RFID
chips with an RC522 reader on a Raspberry Pi. A temporary setup: the Pi is
wiped after use, so there is no monitoring, backup or DHCP reservation, and it
is not part of the homelab repo.

## Commands

- `ansible-playbook playbook.yml`: set up the Pi in `inventory.ini`.
- `bash tests/rfid.test.sh`: the tool's tests, no reader needed.
- `ssh root@<pi> rfid info`: is the reader wired correctly?
- `curl http://<pi>/api/info`: does the web page (service `rfid-web`) see it?

## Rules

- `files/rfid` uses the standard library and `spidev` only (Debian's
  `python3-spidev`); no pip, no venv on the Pi.
- It never writes MIFARE Classic block 0 or a sector trailer, nor an NTAG's
  lock or config pages: a wrong write there bricks a chip.
- The web page is part of `files/rfid` (`rfid serve`): one file, stdlib only.
  Its strings are in `COPY`, English first and German with the same keys
  (the tests check it); error messages from the reader stay English.
- The page has no login and must not be exposed beyond the LAN. POSTs stay
  JSON-only: that is what stops cross-site writes.
- Wiring changes go into the README table, the docstring's `WIRING` line and
  `rfid_rst_gpio` in `playbook.yml` together.
