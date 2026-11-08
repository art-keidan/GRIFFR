# GRIFFR

Object-based typographic word processor for macOS.

GRIFFR is a native macOS app (AppKit, SwiftUI, Core Text) that composes text with typographic care: styles defined by formulas, sections and chapter headings, notes and floats, lists, tables, fields, AAT and OpenType features, and PDF output.

## Requirements

- macOS 14 or later
- Xcode with Swift 6

## Build

```sh
Scripts/build-app.sh
```

The app is created in `build/GRIFFR.app`.

## Tests

```sh
swift test
```

Some tests use fonts installed on the development machine.

## Documents

GRIFFR documents use the `.grx` extension: XML in UTF-8, readable and editable by hand.

## Status

Work in progress.
