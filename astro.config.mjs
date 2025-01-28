import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import tailwind from "@astrojs/tailwind";
import icon from "astro-icon";
import { remarkModifiedTime } from "./src/utils/remark-modified-time";
import remarkDirective from "remark-directive";
import remarkCalloutDirectives from "@microflash/remark-callout-directives"
import githubTheme from '@microflash/remark-callout-directives/config/github'

import { siteConfig } from "./src/config";

// https://astro.build/config
export default defineConfig({
    site: siteConfig.site,
    integrations: [mdx(), sitemap(), tailwind({
        applyBaseStyles: false
    }), icon()],
    markdown: {
        shikiConfig: {
            themes: {
                light: 'one-light',
                dark: 'one-dark-pro'
            }
        },
        remarkPlugins: [
            remarkModifiedTime,
            remarkDirective,
            [remarkCalloutDirectives, githubTheme]
        ]
    },
    devToolbar: {
        enabled: false
    }
});
