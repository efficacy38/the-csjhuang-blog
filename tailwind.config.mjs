/** @type {import('tailwindcss').Config} */
export default {
    content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
    darkMode: 'selector',
    theme: {
        extend: {
            colors: {
                base: 'rgb(var(--color-base))',
                back: 'rgb(var(--color-back))',
                elevated: 'rgb(var(--color-elevated))',
                primary: 'rgb(var(--color-primary))',
                secondary: 'rgb(var(--color-secondary))',
                border: 'rgb(var(--color-border))',
                hover: 'rgb(var(--color-hover))',
                active: 'rgb(var(--color-active))',
                accent: 'rgb(var(--color-accent))',
                'accent-hover': 'rgb(var(--color-accent-hover))',
                'accent-muted': 'rgb(var(--color-accent-muted))',
            },
            fontFamily: {
                mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'Monaco', 'Consolas', 'Liberation Mono', 'Courier New', 'monospace'],
            },
            borderColor: {
                DEFAULT: 'rgb(var(--color-border))',
            },
        },
    },
    plugins: [
        require('@tailwindcss/typography'),
        require('tailwindcss-animate')
    ],
}
