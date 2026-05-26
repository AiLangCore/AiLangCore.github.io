---
title: "Welcome to AiLang Articles"
description: "An example article showing how to write markdown content for the AiLang website"
date: 2026-05-21
author: "Todd Henderson"
---

## Getting Started

This is an example article written in Markdown. Create new articles by adding `.md` files to the `_articles/` directory.

### Front Matter

Each article should start with YAML front matter containing:

- `title`: The article title
- `description`: A brief summary (shown in the articles list)
- `date`: Publication date (YYYY-MM-DD format)
- `author`: Author name (optional)

### Markdown Features

You can use all standard markdown features:

**Bold text**, *italic text*, and `inline code`.

```ailang
// Code blocks with syntax highlighting
func main() {
    print("Hello from AiLang!")
}
```

### Lists

- Unordered lists
- Work as expected
- With multiple items

1. Ordered lists
2. Also work
3. Numbered automatically

### Links and More

[Link to AiLang GitHub](https://github.com/AiLangCore/AiLang)

> Blockquotes are also supported for highlighting important information.

## Building Articles

Run `npm run build` to convert all markdown files to HTML pages under `_site/articles/`.
