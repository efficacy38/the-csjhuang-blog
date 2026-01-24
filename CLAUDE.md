# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A personal blog built with Astro (v5) using the "Astro Blur" theme. Static site deployed to GitHub Pages at https://blog.csjhuang.net.

## Commands

```bash
pnpm dev          # Start development server
pnpm build        # Type-check and build (runs astro check && astro build)
pnpm preview      # Preview production build locally
pnpm new "Title"  # Create new blog post
```

### New Post Options

```bash
pnpm new "Title"                      # Creates published post in src/content/posts/
pnpm new -d "Title"                   # Creates draft in src/content/drafts/
pnpm new -s "custom-slug" "Title"     # Custom URL slug
pnpm new -t tag1 -t tag2 "Title"      # Add tags (defaults to "unclassified")
```

## Architecture

### Content Collections (`src/content.config.ts`)

- **posts**: Blog posts in `src/content/posts/` (md/mdx)
- **pages**: Static pages in `src/content/pages/` (md/mdx)
- **links**: Friend links in `src/content/data/links.json`
- **projects**: Projects in `src/content/data/projects.json`

### Post Frontmatter Schema

```yaml
title: string (required)
description: string (required)
pubDate: date (required)
slug: string (required)
isDraft: boolean (optional)
tags: string[] (optional)
```

### Layout Hierarchy

- `BaseLayout.astro` → HTML structure, theme initialization
- `MainLayout.astro` → Blog listing pages
- `PageLayout.astro` → Individual post/page display with table of contents

### Key Configuration

- `src/config.ts` - Site metadata, navigation, social links
- `astro.config.mjs` - Astro integrations, markdown plugins
- `tailwind.config.mjs` - Theme colors via CSS variables, dark mode

### Content Routing

- Posts tagged with "note" appear only in `/notes`, not on main blog index
- Draft posts (`isDraft: true`) are hidden in production builds

### Search

Pagefind indexes content marked with `[data-pagefind-body]` attribute during postbuild.
