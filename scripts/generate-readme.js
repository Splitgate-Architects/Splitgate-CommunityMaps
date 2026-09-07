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
                console.warn(`Could not read Info.json from ${map.bin}: ${e.message}`);
            }

            const relDir = `Maps/${folderName}`;
            
            // Für die Haupt-README brauchen wir den Pfad mit "Maps/ordnername/bild.jpg"
            const imgTagMain = map.jpg ? `![${map.id}](${relDir}/${map.jpg})` : `*(No image)*`;
            // Für die Unterordner-README reicht nur der Dateiname
            const imgTagSub = map.jpg ? `![${map.id}](${map.jpg})` : `*(No image)*`;

            const binLink = `[📥 Download .bin](${REPO_URL}/${relDir}/${map.bin})`;

            currentRow.push({
                imgMain: imgTagMain,
                imgSub: imgTagSub,
                info: `**${displayName}**<br>by ${author}`,
                download: binLink
            });
        });

        while (currentRow.length < 3) {
            currentRow.push({ imgMain: '&nbsp;', imgSub: '&nbsp;', info: '&nbsp;', download: '&nbsp;' });
        }

        // Wir bauen die Zeilen für die Unterordner-README zusammen
        markdown += `| ${currentRow.map(c => c.imgSub).join(' | ')} |\n`;
        markdown += `| :---: | :---: | :---: |\n`;
        markdown += `| ${currentRow.map(c => c.info).join(' | ')} |\n`;
        markdown += `| ${currentRow.map(c => c.download).join(' | ')} |\n\n`;
    }

    fs.writeFileSync(path.join(targetDir, 'README.md'), markdown);
    console.log(`README generated for ${folderName}.`);

    // Wir geben ein Objekt zurück, damit die Haupt-README die angepassten Bild-Tags nutzen kann
    return {
        tableMarkdown: items.reduce((acc, _, i) => acc, ""), // Platzhalter, wir machen es unten direkt sauber
        rawItems: items,
        folder: folderName
    };
}

function generateMainReadme() {
    const templatePath = path.join(__dirname, 'generate-readme.md');
    let baseContent = "";
    
    if (fs.existsSync(templatePath)) {
        baseContent = fs.readFileSync(templatePath, 'utf8').trim();
    } else {
        console.warn("generate-readme.md not found in scripts folder!");
    }

    let mainMarkdown = baseContent ? `${baseContent}\n\n` : "";
    mainMarkdown += `## Maps\n\n`;

    SUBFOLDERS.forEach(folder => {
        const targetDir = path.join(BASE_DIR, folder);
        if (!fs.existsSync(targetDir)) return;

        // Lass uns die Tabellenstruktur für die Haupt-README direkt mit den korrekten Hauptpfaden bauen
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
        
        // Erst die Unterordner-README generieren (schreibt die Unterordner-Dateien)
        generateSubfolderReadme(folder);

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

            tableMarkdown += `| ${currentRow.map(c => c.img).join(' | ')} |\n`;
            tableMarkdown += `| :---: | :---: | :---: |\n`;
            tableMarkdown += `| ${currentRow.map(c => c.info).join(' | ')} |\n`;
            tableMarkdown += `| ${currentRow.map(c => c.download).join(' | ')} |\n\n`;
        }

        mainMarkdown += `<details>\n`;
        mainMarkdown += `<summary><b>${folder} Maps</b> (Click to expand)</summary>\n\n`;
        mainMarkdown += tableMarkdown;
        mainMarkdown += `</details>\n\n`;
    });

    const rootReadmePath = path.join(__dirname, '../README.md');
    fs.writeFileSync(rootReadmePath, mainMarkdown);
    console.log('Main README.md successfully generated with correct image paths!');
}

generateMainReadme();