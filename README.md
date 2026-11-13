# GRIFFR

Object-based typographic word processor for macOS.

GRIFFR is a native macOS app (AppKit, SwiftUI, Core Text) for writing and typesetting in the same place.

## What it does

- **Every font technology.** AAT (`morx` features and selectors), OpenType features, Graphite (when installed on the system), variable fonts with their axes and optical sizes, and color fonts in every format (`sbix`, `COLR` v0 and v1, `SVG`), in color both on screen and in the PDF.
- **Layout as objects.** A document is made of objects (paragraphs, sections, chapter headings, notes, floats, lists, tables, fields) that are combined through functions: a style is a set of formulas, a field is a chain that reads a result from other objects and writes it where it stands, a heading composes its parts around the title. All of this is built visually, with blocks, not written as code.
- **Three levels of interface.**
  - *Simple*: only what you need to write.
  - *Advanced*: every setting of the document, its styles, lists, floats, pages and tables.
  - *Visual*: the same settings, set by hand on the page (Design Paragraph) and in the style composer.
- **PDF output** from the same composition shown on screen.

## Guide

A short visual guide, with screenshots of every part of the interface: [docs/index.html](docs/index.html). Open it in a browser, or publish the `docs` folder with GitHub Pages. The same guide as a PDF: [docs/GRIFFR-guide.pdf](docs/GRIFFR-guide.pdf).

The screenshots are made by the app itself: `GRIFFR_GUIDE_OUT="$PWD/docs/guide/images/full" swift test --filter GuideScreenshotTests`, then `swift Scripts/guide-crops.swift docs/guide/images/full docs/guide/images`. The tabs of the Definitions panel are taken from the running app.

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

Sample documents for automated and manual testing are in [Tests/Fixtures](Tests/Fixtures/). Some tests use fonts installed on the development machine.

## Documents

GRIFFR documents use the `.grx` extension: XML in UTF-8, readable and editable by hand.

## Status

Work in progress.
