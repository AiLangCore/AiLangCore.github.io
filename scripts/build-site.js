#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { marked } = require('marked');
const matter = require('gray-matter');

const ROOT = path.join(__dirname, '..');
const SITE_DIR = path.join(ROOT, '_site');
const ARTICLES_SRC = path.join(ROOT, '_articles');
const ARTICLES_DIST = path.join(SITE_DIR, 'articles');

const STATIC_ENTRIES = [
  'CNAME',
  'assets',
  'docs',
  'index.html',
  'install.ps1',
  'install.sh',
  'styles.css'
];

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function formatDate(value) {
  if (!value) {
    return '';
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid article date: ${value}`);
  }

  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  });
}

function copyStaticSite() {
  fs.rmSync(SITE_DIR, { recursive: true, force: true });
  fs.mkdirSync(SITE_DIR, { recursive: true });

  for (const entry of STATIC_ENTRIES) {
    const source = path.join(ROOT, entry);
    const destination = path.join(SITE_DIR, entry);

    if (!fs.existsSync(source)) {
      continue;
    }

    fs.cpSync(source, destination, { recursive: true });
  }
}

function articleTemplate(article) {
  const safeTitle = escapeHtml(article.title);
  const safeAuthor = escapeHtml(article.author);
  const dateLine = article.date
    ? `<p class="tagline">${escapeHtml(formatDate(article.date))}${safeAuthor ? ` · ${safeAuthor}` : ''}</p>`
    : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${safeTitle} - AiLang</title>
    <link rel="stylesheet" href="../styles.css" />
</head>
<body>

<header class="container doc-page-header">
    <nav class="top-nav" aria-label="Primary">
        <a href="../index.html">Home</a>
        <a href="../docs/quickstart.html">Quickstart</a>
        <a href="./index.html">Articles</a>
        <a href="https://github.com/sponsors/AiLangCore" class="sponsor-link">Sponsor</a>
    </nav>
    <h1>${safeTitle}</h1>
    ${dateLine}
</header>

<main class="container doc-page article-content">
${article.contentHtml}
</main>

<footer class="container footer">
    <p>&copy; 2026 Todd Henderson</p>
</footer>

</body>
</html>
`;
}

function articlesIndexTemplate(articles) {
  const articlesHtml = articles.length > 0
    ? articles
      .map((article) => `        <a href="${encodeURIComponent(article.slug)}.html">
            <strong>${escapeHtml(article.title)}</strong>
            ${article.date ? `<span class="article-date">${escapeHtml(formatDate(article.date))}</span>` : ''}
            ${article.description ? `<span class="article-description">${escapeHtml(article.description)}</span>` : ''}
        </a>`)
      .join('\n')
    : '        <p class="muted">No articles have been published yet.</p>';

  return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Articles - AiLang</title>
    <link rel="stylesheet" href="../styles.css" />
</head>
<body>

<header class="container doc-page-header">
    <nav class="top-nav" aria-label="Primary">
        <a href="../index.html">Home</a>
        <a href="../docs/quickstart.html">Quickstart</a>
        <a href="https://github.com/sponsors/AiLangCore" class="sponsor-link">Sponsor</a>
    </nav>
    <h1>Articles</h1>
    <p class="tagline">Project updates, technical notes, and release context for AiLangCore.</p>
</header>

<main class="container doc-page">
    <section class="articles-list">
${articlesHtml}
    </section>
</main>

<footer class="container footer">
    <p>&copy; 2026 Todd Henderson</p>
</footer>

</body>
</html>
`;
}

function readArticles() {
  if (!fs.existsSync(ARTICLES_SRC)) {
    return [];
  }

  return fs.readdirSync(ARTICLES_SRC)
    .filter((file) => file.endsWith('.md'))
    .sort()
    .map((file) => {
      const filePath = path.join(ARTICLES_SRC, file);
      const fileContent = fs.readFileSync(filePath, 'utf8');
      const { data, content } = matter(fileContent);
      const slug = path.basename(file, '.md');

      return {
        slug,
        title: data.title || slug,
        description: data.description || '',
        date: data.date || null,
        author: data.author || '',
        contentHtml: marked(content)
      };
    })
    .sort((left, right) => {
      const leftDate = left.date ? new Date(left.date).getTime() : 0;
      const rightDate = right.date ? new Date(right.date).getTime() : 0;
      return rightDate - leftDate || left.slug.localeCompare(right.slug);
    });
}

function buildArticles() {
  fs.mkdirSync(ARTICLES_DIST, { recursive: true });

  const articles = readArticles();
  for (const article of articles) {
    const html = articleTemplate(article);
    fs.writeFileSync(path.join(ARTICLES_DIST, `${article.slug}.html`), html);
    console.log(`Built article: ${article.slug}`);
  }

  fs.writeFileSync(path.join(ARTICLES_DIST, 'index.html'), articlesIndexTemplate(articles));
  console.log(`Built articles index: ${articles.length} article(s)`);
}

copyStaticSite();
buildArticles();
console.log(`Built site: ${SITE_DIR}`);
