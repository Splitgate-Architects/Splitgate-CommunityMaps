import fs from 'fs';
import path from 'path';

const TARGET_DIR = './Maps/Playable'; // Anpassen je nach Ordner
const REPO_URL = 'https://cdn.jsdelivr.net/gh/DEIN-BENUTZERNAME/DEIN-REPO@master';

function generateMarkdown() {
    if (!fs.existsSync(TARGET_DIR)) {
        console.error(`Ordner ${TARGET_DIR} nicht gefunden!`);
        return;
    }

    const files = fs.readdirSync(TARGET_DIR);
    const maps = {};

    // Sammle alle zusammengehörenden Dateien (.bin, .jpg, .json)
    files.forEach(file => {
        const ext = path.extname(file);
        const baseName = path.basename(file, ext);

        if (!maps[baseName]) {
            maps[baseName] = { id: baseName };
        }
        maps[baseName][ext.replace('.', '')] = file;
    });

    let markdown = `# Playable Maps\n\nEine kuratierte Liste aller spielbaren Maps.\n\n`;
    
    let items = Object.values(maps);
    let currentRow = [];

    items.forEach((map, index) => {
        let name = map.id;
        let author = "Unknown";

        // Versuche, Name und Author aus der .json zu lesen, falls vorhanden
        if (map.json) {
            try {
                const jsonPath = path.join(TARGET_DIR, map.json);
                const jsonData = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
                if (jsonData.name) name = jsonData.name;
                if (jsonData.author) author = jsonData.author;
            } catch (e) {
                console.warn(`Konnte JSON nicht lesen für ${map.id}`);
            }
        } else {
            // Fallback: Aus Dateinamen parsen (author_mapname)
            const parts = map.id.split('_');
            if (parts.length >= 2) {
                author = parts[0];
                name = parts.slice(1).join(' ');
            }
        }

        const imgTag = map.jpg 
            ? `![${name}](${TARGET_DIR}/${map.jpg})` 
            : `*(Kein Bild)*`;
            
        const binLink = map.bin 
            ? `[📥 Download .bin](${REPO_URL}/${TARGET_DIR}/${map.bin})` 
            : `*Keine .bin*`;

        currentRow.push({
            img: imgTag,
            info: `**${name}**<br>by ${author}`,
            download: binLink
        });

        // Wenn 3 Spalten voll sind oder es das letzte Element ist, Zeile schreiben
        if (currentRow.length === 3 || index === items.length - 1) {
            // Zeile 1: Bilder
            markdown += `| ${currentRow.map(c => c.img).join(' | ')} |\n`;
            // Trenner
            markdown += `| :---: | :---: | :---: |\n`;
            // Zeile 2: Name & Autor
            markdown += `| ${currentRow.map(c => c.info).join(' | ')} |\n`;
            // Zeile 3: Downloads
            markdown += `| ${currentRow.map(c => c.download).join(' | ')} |\n\n`;

            currentRow = [];
        }
    });

    fs.writeFileSync(path.join(TARGET_DIR, 'README.md'), markdown);
    console.log('README erfolgreich generiert!');
}

generateMarkdown();