// Development-only visual verification; Sharp is not a production dependency.
const path = require('node:path');
const sharp = require(process.argv[2] || 'sharp');
const root = path.resolve(__dirname, '..');
sharp(path.join(root, 'tmp/proposed-dns-failover.svg'))
    .png()
    .toFile(path.join(root, 'tmp/proposed-dns-failover.png'))
    .then(function () { console.log('Rendered tmp/proposed-dns-failover.png'); })
    .catch(function (error) { console.error(error); process.exitCode = 1; });
