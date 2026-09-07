import fs from 'fs';
import path from 'path';
import AdmZip from 'adm-zip';

const BASE_DIR = './Maps';
const SUBFOLDERS = ['Playable', 'Unplayable', 'WIP'];
const REPO_URL = 'https://cdn.jsdelivr.net/gh/Splitgate-Architects/Splitgate-CommunityMaps@master';

function generateMarkdownForFolder(folderName) {
    const targetDir = path.join(BASE_DIR, folderName);

    if (!fs.existsSync(targetDir)) {
        console.warn(`Ordner ${targetDir} nicht gefunden. Wird übersprungen.`);
        return;
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

    let markdown = `# ${folderName} Maps\n\nEine Übersicht aller Maps in der Kategorie **${folderName}**.\n\n`;
    
    let items = Object.values(maps)
        .filter(m => m.bin)
        .sort((a, b) => a.id.localeCompare(b.id));

    for (let i = 0; i < items.length; i += 3) {
        let chunk = items.slice(i, i + 3);
        let currentRow = [];

        chunk.forEach(map => {
            let displayName = map.id;
            let author = "Unknown";

            // Fallback aus Dateinamen
            const parts = map.id.split('_');
            if (parts.length >= 3) {
                author = parts[1];
                displayName = parts.slice(2).join(' ');
            } else if (parts.length === 2) {
                author = parts[0];
                displayName = parts[1];
            }

            // Info.json auslesen für den echten Anzeigenamen
            try {
                const binPath = path.join(targetDir, map.bin);
                const zip = new AdmZip(binPath);
                const zipEntries = zip.getEntries();
                
                const infoEntry = zipEntries.find(entry => entry.entryName.toLowerCase() === 'info.json');

                if (infoEntry) {
                    let jsonContent = infoEntry.getData().toString('utf8').trim();
                    jsonContent = jsonContent.replace(/^\uFEFF/, ''); 
                    
                    const jsonData = JSON.parse(jsonContent);
                    if (jsonData.name) displayName = jsonData.name;
                    if (jsonData.author) author = jsonData.author;
                }
            } catch (e) {
                console.warn(`Konnte Info.json aus ${map.bin} nicht lesen: ${e.message}`);
            }

            const relDir = `${BASE_DIR.replace('./', '')}/${folderName}`;
            
            // WICHTIG: Hier konsequent den echten Dateinamen (.jpg) nutzen, 
            // damit Markdown wegen Sonderzeichen im JSON-Namen (wie "|") nicht stolpert!
            const imgTag = map.jpg ? `![${map.id}](${map.jpg})` : `*(Kein Bild)*`;
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

        markdown += `| ${currentRow.map(c => c.img).join(' | ')} |\n`;
        markdown += `| :---: | :---: | :---: |\n`;
        markdown += `| ${currentRow.map(c => c.info).join(' | ')} |\n`;
        markdown += `| ${currentRow.map(c => c.download).join(' | ')} |\n\n`;
    }

    fs.writeFileSync(path.join(targetDir, 'README.md'), markdown);
    console.log(`README für ${folderName} erfolgreich generiert!`);
}

SUBFOLDERS.forEach(folder => generateMarkdownForFolder(folder));