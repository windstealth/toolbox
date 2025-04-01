const fs = require('fs');

// Get the file path from command line arguments
const filePath = process.argv[2];
const DELIMITER = "==============================";

// Read the SSH config file
const fileContent = fs.readFileSync(filePath, 'utf-8');

// Split the content into non-empty lines
const lines = fileContent.split('\n').filter(Boolean);
let hostLines = [];  // Store the current block being built
const blocks = [];

// Split content into blocks based on "Host" entries
lines.forEach((line, i) => {
  if (line.startsWith('Host') || i === lines.length - 1) {
    if (hostLines.length > 0) {
      if (i === lines.length - 1) {
        hostLines.push(line);
      }
      blocks.push(hostLines.join("\n"));
    }
    hostLines = [line];
  } else if (line && !line.startsWith('#')) {
    hostLines.push(line);
  }
});

// Arrays to hold global and host blocks
const globals = [];
const hosts = [];

// Process each block, classifying as global or host block
blocks.forEach((block) => {
  const cleanedBlock = block.split('\n').filter(line => line && !line.startsWith('#')).join('\n');
  if (cleanedBlock.startsWith('Host *')) {
    globals.push(cleanedBlock);
  } else {
    hosts.push(cleanedBlock);
  }
});

// Sort the global and host blocks
const sortedGlobals = globals.sort();
const sortedHosts = hosts.sort();

// Format host blocks with additional comments
const formattedHosts = sortedHosts.map(host => {
  const [hostKind, domain] = host.split('\n')[0].split('.');
  let formattedHost = `\n${host}`;

  if (hostKind === 'Host github') {
    formattedHost = `\n# ${DELIMITER}\n# GitHub [${domain}] Server\n# ${DELIMITER}${formattedHost}`;
  } else if (hostKind === 'Host ssh') {
    formattedHost = `\n# ${DELIMITER}\n# SSH [${domain}] Server\n# ${DELIMITER}${formattedHost}`;
  }

  return formattedHost;
});

// Combine the global and host blocks into the final content
const content = `# ${DELIMITER}\n# Global SSH settings\n# ${DELIMITER}\n${sortedGlobals.join('\n')}\n${formattedHosts.join('\n')}`.trim();

// Write the formatted content back to the file
fs.writeFileSync(filePath, content);
console.log("✅ SSH config sorted and updated successfully!");
