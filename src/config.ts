export const siteConfig: SiteConfig = {
    title: "Hi! Csjhuang",
    language: "zh",
    description: "Csjhuang's personal blog. Powered by Astro Blog Theme Blur.",
    keywords: "csjhuang, blog, personal blog, Astro, Astro Blog Theme Blur",
    author: "Csjhuang",
    avatar: "/avatar.png",
    favicon: "/favicon.png",
    site: "https://blog.csjhuang.net",

    page_size: 10,
};

export const navBarConfig: NavBarConfig = {
    links: [
        {
            name: "Tags",
            url: "/tags",
        },
        {
            name: "Notes",
            url: "/notes",
        },
        {
            name: "Projects",
            url: "/projects",
        },
        {
            name: "Links",
            url: "/links",
        },
        {
            name: "About",
            url: "/about",
        },
    ],
};

export const socialLinks: SocialLink[] = [
    // https://icon-sets.iconify.design/material-symbols/
    {
        label: "GitHub",
        icon: "mdi-github",
        url: "https://github.com/efficacy38",
    },
    {
        label: "Email",
        icon: "material-symbols:mail-rounded",
        url: "mailto:efficacy38@proton.me",
    },
];

interface SiteConfig {
    title: string;
    language: string;
    description: string;
    keywords: string;
    author: string;
    avatar: string;
    favicon: string;
    site: string;

    page_size: number;
    twikoo_uri?: string; // https://twikoo.js.org/
}

interface NavBarConfig {
    links: {
        name: string;
        url: string;
        target?: string;
    }[];
}

interface SocialLink {
    label: string;
    icon: string;
    url: string;
}
