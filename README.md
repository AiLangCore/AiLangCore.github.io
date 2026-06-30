# AiLangCore Website

This repository publishes the public AiLangCore website.

## Scope

- Project landing page.
- Public install scripts.
- Human-facing documentation entry points.
- Release and sponsorship links.
- Public roadmap.

## Status

This repository uses `main` as the public GitHub Pages branch. Website changes
are published from `main`; release artifacts remain owned by the individual
AiLang, AiVM, and AiVectra repositories.

Public roadmap:

- https://ailang.codes/docs/roadmap.html

## Local Preview

Install the site dependencies once:

```bash
npm ci
```

Build the static site:

```bash
npm run build
```

Open `_site/index.html` directly in a browser.

## Articles

Article source files live in `_articles/*.md`. Each article should use YAML
front matter:

```md
---
title: "Article title"
description: "Short summary shown on the article index"
date: 2026-05-26
author: "Author name"
---

Article body in Markdown.
```

Pushing to `main` runs the GitHub Pages workflow, builds `_site`, and publishes
the generated article pages.

## Public Beta Set

- AiLang SDK `v0.0.1-beta.22`
- AiVM `v0.0.1-rc.3`
- Official target packages:
  - `target-aios-gui` / `target-aios-service` `v0.0.1-alpha.5`
  - `target-wasm` `v0.0.1-alpha.3`
  - `target-linux` `v0.0.1-alpha.4`
  - `target-macos`, `target-windows` `v0.0.1-alpha.2`

The install scripts assemble these tools from their release artifacts through
the beta channel. Target packages are restored through the curated package
registry.
