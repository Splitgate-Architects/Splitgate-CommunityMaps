import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import AdmZip from 'adm-zip';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BASE_DIR = path.join(__dirname, '../Maps');
const SUBFOLDERS = ['Playable', 'WIP', 'Unplayable'];
const REPO_URL = 'https://cdn.jsdelivr.net/gh/Splitgate-Architects/Splitgate-CommunityMaps@master';

function generateSubfolderReadme(folderName) {
    const targetDir = path.join(BASE_DIR, folderName);

    if (!fs.existsSync(targetDir)) {
        console.warn(`Folder ${targetDir} not found. Skipping.`);
        return "";
    }

    const files = fs.readdirSync(targetDir);
    const maps = {};

    files.forEach(file => {
        if (file.toLowerCase() === 'readme.md') return; 
        
        const ext = path.extname(file);
        if (!['.bin', '.jpg'].includes(ext)) return;

        const baseName = path.basename(file, ext);

        if (!maps[baseName]) {
            maps[baseName] = { id: baseName };
        }
        maps[baseName][ext.replace('.', '')] = file;
    });

    let markdown = `# ${folderName} Maps\n\nAn overview of all maps in the **${folderName}** category.\n\n`;
    
    let items = Object.values(maps)
        .filter(m => m.bin)
        .sort((a, b) => a.id.localeCompare(b.id));

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

            const imgTag = map.jpg ? `![${map.id}](${map.jpg})` : `*(No image)*`;
            const binLink = `[📥 Download .bin](${REPO_URL}/Maps/${folderName}/${map.bin})`;

            currentRow.push({
                img: imgTag,
                info: `**${displayName}**<br>by ${author}`,
                download: binLink
            });
        });

        while (currentRow.length < 3) {
            currentRow.push({ img: '&nbsp;', info: '&nbsp;', download: '&nbsp;' });
        }

        // HTML Tablebau für den Unterordner
        markdown += `<table>\n`;
        markdown += `  <tr>\n`;
        currentRow.forEach(c => markdown += `    <td align="center">${c.img}</td>\n`);
        markdown += `  </tr>\n`;
        markdown += `  <tr>\n`;
        currentRow.forEach(c => markdown += `    <td align="center">${c.info}</td>\n`);
        markdown += `  </tr>\n`;
        markdown += `  <tr>\n`;
        currentRow.forEach(c => markdown += `    <td align="center">${c.download}</td>\n`);
        markdown += `  </tr>\n`;
        markdown += `</table>\n\n`;
    }

    fs.writeFileSync(path.join(targetDir, 'README.md'), markdown);
}

function generateMainReadme() {
    const templatePath = path.join(__dirname, 'generate-readme.md');
    let baseContent = fs.existsSync(templatePath) ? fs.readFileSync(templatePath, 'utf8').trim() : "";

    let mainMarkdown = baseContent ? `${baseContent}\n\n` : "";
    mainMarkdown += `## Maps\n\n`;

    SUBFOLDERS.forEach(folder => {
        const targetDir = path.join(BASE_DIR, folder);
        if (!fs.existsSync(targetDir)) return;

        generateSubfolderReadme(folder);

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

            // HTML Tablebau für die Haupt-README
            tableMarkdown += `<table>\n`;
            tableMarkdown += `  <tr>\n`;
            currentRow.forEach(c => tableMarkdown += `    <td align="center">${c.img}</td>\n`);
            tableMarkdown += `  </tr>\n`;
            tableMarkdown += `  <tr>\n`;
            currentRow.forEach(c => tableMarkdown += `    <td align="center">${c.info}</td>\n`);
            tableMarkdown += `  </tr>\n`;
            tableMarkdown += `  <tr>\n`;
            currentRow.forEach(c => tableMarkdown += `    <td align="center">${c.download}</td>\n`);
            tableMarkdown += `  </tr>\n`;
            tableMarkdown += `</table>\n\n`;
        }

        mainMarkdown += `<details>\n`;
        mainMarkdown += `<summary><b>${folder} Maps</b> (Click to expand)</summary>\n\n`;
        mainMarkdown += tableMarkdown;
        mainMarkdown += `</details>\n\n`;
    });

    const rootReadmePath = path.join(__dirname, '../README.md');
    fs.writeFileSync(rootReadmePath, mainMarkdown);
    console.log('Main README.md successfully generated with HTML tables!');
}

generateMainReadme();