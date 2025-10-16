const express = require("express");
const fs = require("fs");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const DATA_FILE = "/data/counter.txt";

// Ensure data directory exists
const dataDir = path.dirname(DATA_FILE);
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// Initialize counter file if it doesn't exist
if (!fs.existsSync(DATA_FILE)) {
  fs.writeFileSync(DATA_FILE, "0");
}

// Read current count
function getCount() {
  try {
    return parseInt(fs.readFileSync(DATA_FILE, "utf8").trim() || "0");
  } catch (err) {
    return 0;
  }
}

// Write count
function setCount(count) {
  fs.writeFileSync(DATA_FILE, count.toString());
}

app.get("/", (req, res) => {
  const count = getCount();
  const newCount = count + 1;
  setCount(newCount);

  res.send(`
    <html>
      <head><title>Visitor Counter - OpenEBS Demo</title></head>
      <body style="font-family: Arial; text-align: center; padding: 50px;">
        <h1>🎯 OpenEBS Persistence Demo</h1>
        <h2>Total Visits: ${newCount}</h2>
        <p>Pod: ${process.env.HOSTNAME || "unknown"}</p>
        <p>Data stored at: ${DATA_FILE}</p>
        <p style="color: #666; font-size: 14px;">
          Try deleting the pod - the counter will persist!
        </p>
      </body>
    </html>
  `);
});

app.get("/health", (req, res) => {
  res.json({ status: "healthy", count: getCount() });
});

app.get("/reset", (req, res) => {
  setCount(0);
  res.send("Counter reset to 0");
});

app.listen(PORT, () => {
  console.log(`Visitor counter running on port ${PORT}`);
  console.log(`Current count: ${getCount()}`);
});
