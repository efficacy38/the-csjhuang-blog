import fs from "fs"
import path from "path"
import yargs from "yargs"
import { hideBin } from "yargs/helpers"

function getDate() {
    const today = new Date()
    const year = today.getFullYear()
    const month = today.getMonth() + 1
    const day = today.getDate()
    return `${year}-${month < 10 ? "0" : ""}${month}-${day < 10 ? "0" : ""}${day}`
}

const argv = yargs(hideBin(process.argv))
    .option('slug', {
        alias: 's',
        type: 'string',
        description: 'The slug for the new post'
    })
    .option('draft', {
        alias: 'd',
        type: 'boolean',
        description: 'Mark the post as a draft'
    })
    .option('tag', {
        alias: 't',
        type: 'string',
        description: 'A tag for the new post (can be specified multiple times)'
    })
    .positional('title', {
        type: 'string',
        description: 'The title of the new post'
    })
    .demandCommand(1, 'You need to provide a title for the new post.')
    .parse()

const title = argv._[0]
const slug = (argv.slug || title).replace(/\s+/g, '-')
const isDraft = argv.draft

let tags = argv.tag
if (!tags) {
    tags = ['unclassified']
} else if (!Array.isArray(tags)) {
    tags = [tags]
}

let fileName = slug
const fileExtensionRegex = /\.(md|mdx)$/i
if (!fileExtensionRegex.test(fileName)) {
    fileName += ".md"
}

const targetDir = isDraft ? "./src/content/drafts/" : "./src/content/posts/"
if (isDraft && !fs.existsSync(targetDir)) {
    fs.mkdirSync(targetDir, { recursive: true })
}
const fullPath = path.join(targetDir, fileName)

if (fs.existsSync(fullPath)) {
    console.error(`Error：File ${fullPath} already exists `)
    process.exit(1)
}

let content = `---
title: ${title}
description: ${title}
pubDate: ${getDate()}
slug: ${slug}
`

if (isDraft) {
    content += `draft: true
`
}

content += `tags:
${tags.map(tag => `    -"${tag}"`).join('\n')}
---
`

fs.writeFileSync(path.join(targetDir, fileName), content)

console.log(`Post ${fullPath} created`)