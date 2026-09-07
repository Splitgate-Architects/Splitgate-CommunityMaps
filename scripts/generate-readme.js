import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import AdmZip from 'adm-zip';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BASE_DIR = path.join(__dirname, '../Maps');
const SUBFOLDERS = ['Playable', 'WIP', 'Unplayable', 'Unsorted', 'Templates'];
const REPO_URL = 'https://cdn.jsdelivr.net/gh/Splitgate-Architects/Splitgate-CommunityMaps@master';
const SITE_URL = 'https://splitgate-architects.github.io/Splitgate-CommunityMaps';

function generateMainScript() {
    const templatePath = path.join(__dirname, 'generate-readme.md');
    let baseContent = fs.existsSync(templatePath) ? fs.readFileSync(templatePath, 'utf8').trim() : "";

    let mainMarkdown = baseContent ? `${baseContent}\n\n` : "";
    mainMarkdown += `## Maps\n\n`;

    let allMapsData = [];

    SUBFOLDERS.forEach(folder => {
        const targetDir = path.join(BASE_DIR, folder);
        if (!fs.existsSync(targetDir)) return;

        const files = fs.readdirSync(targetDir);
        const maps = {};

        files.forEach(file => {
            if (file.toLowerCase() === 'readme.md') return;
            const ext = path.extname(file);
            if (!['.bin', '.jpg'].includes(ext)) return;
            const baseName = path.basename(file, ext);
            if (!maps[baseName]) maps[baseName] = { id: baseName };
            maps[baseName][ext.replace('.', '')] = file;
        });

        let items = Object.values(maps).filter(m => m.bin).sort((a, b) => a.id.localeCompare(b.id));
        
        let subfolderMarkdown = `# ${folder} Maps\n\nAn overview of all maps in the **${folder}** category.\n\n`;
        let tableMarkdown = "";

        for (let i = 0; i < items.length; i += 3) {
            let chunk = items.slice(i, i + 3);
            let currentRow = [];

            chunk.forEach(map => {
                let displayName = map.id;
                let author = "Unknown";
                const parts = map.id.split('_');
                if (parts.length >= 3) {
                    author = parts[1];
                    displayName = parts.slice(2).join(' ');
                } else if (parts.length === 2) {
                    author = parts[0];
                    displayName = parts[1];
                }

                try {
                    const binPath = path.join(targetDir, map.bin);
                    const zip = new AdmZip(binPath);
                    const infoEntry = zip.getEntries().find(e => e.entryName.toLowerCase() === 'info.json');
                    if (infoEntry) {
                        let jsonContent = infoEntry.getData().toString('utf8').trim().replace(/^\uFEFF/, '');
                        const jsonData = JSON.parse(jsonContent);
                        if (jsonData.name) displayName = jsonData.name;
                        if (jsonData.author) author = jsonData.author;
                    }
                } catch (e) {}

                allMapsData.push({
                    category: folder,
                    id: map.id,
                    name: displayName,
                    author: author,
                    image: map.jpg ? `Maps/${folder}/${map.jpg}` : null,
                    download: `${REPO_URL}/Maps/${folder}/${map.bin}`
                });

                displayName = displayName.replace(/\|/g, '&#124;');
                author = author.replace(/\|/g, '&#124;');

                const relDir = `Maps/${folder}`;
                const imgTag = map.jpg ? `![${map.id}](${relDir}/${map.jpg})` : `*(No image)*`;
                const binLink = `[📥 Download .bin](${REPO_URL}/${relDir}/${map.bin})`;

                currentRow.push({
                    img: imgTag,
                    info: `**${displayName}**<br>by ${author}`,
                    download: binLink
                });
            });

            while (currentRow.length < 3) {
                currentRow.push({ img: '&nbsp;', info: '&nbsp;', download: '&nbsp;' });
            }

            tableMarkdown += `| ${currentRow.map(c => c.img).join(' | ')} |\n`;
            tableMarkdown += `| :---: | :---: | :---: |\n`;
            tableMarkdown += `| ${currentRow.map(c => c.info).join(' | ')} |\n`;
            tableMarkdown += `| ${currentRow.map(c => c.download).join(' | ')} |\n\n`;
        }

        subfolderMarkdown += tableMarkdown;
        fs.writeFileSync(path.join(targetDir, 'README.md'), subfolderMarkdown);

        mainMarkdown += `<details>\n`;
        mainMarkdown += `<summary><b>${folder} Maps</b> (Click to expand)</summary>\n\n`;
        mainMarkdown += tableMarkdown;
        mainMarkdown += `</details>\n\n`;
    });

    const rootReadmePath = path.join(__dirname, '../README.md');
    fs.writeFileSync(rootReadmePath, mainMarkdown);

    const jsonPath = path.join(__dirname, '../maps.json');
    fs.writeFileSync(jsonPath, JSON.stringify(allMapsData, null, 2));

    // --- HTML-Dateien für Discord-Vorschau generieren ---
    const assetsDir = path.join(__dirname, '../assets');
    const shareDir = path.join(assetsDir, 'maps');
    
    if (!fs.existsSync(assetsDir)) fs.mkdirSync(assetsDir);
    if (!fs.existsSync(shareDir)) fs.mkdirSync(shareDir);

    allMapsData.forEach(map => {
        const imageUrl = map.image 
            ? `${REPO_URL}/${map.image}` 
            : `${SITE_URL}/assets/default-banner.jpg`;

        const htmlContent = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${map.name} - Splitgate Custom Map</title>
    
    <meta property="og:type" content="website">
    <meta property="og:title" content="${map.name}">
    <meta property="og:description" content="Map by ${map.author} | Category: ${map.category}">
    <meta property="og:image" content="${imageUrl}">
    <meta name="theme-color" content="#3b82f6">
    
    <meta property="twitter:card" content="summary_large_image">
    <meta property="twitter:title" content="${map.name}">
    <meta property="twitter:description" content="Map by ${map.author} | Category: ${map.category}">
    <meta property="twitter:image" content="${imageUrl}">
    
    <meta http-equiv="refresh" content="0; url=../../index.html#${map.id}">
    <script>
        window.location.replace("../../index.html#${map.id}");
    </script>
</head>
<body style="background: #0f172a; color: #f8fafc; font-family: sans-serif; text-align: center; padding-top: 50px;">
    <p>Redirecting to map...</p>
    <a href="../../index.html#${map.id}" style="color: #3b82f6;">Click here if you are not redirected</a>
</body>
</html>`;

        fs.writeFileSync(path.join(shareDir, `${map.id}.html`), htmlContent);
    });

    console.log('READMEs, maps.json and shareable HTML files successfully generated!');
}

generateMainScript();