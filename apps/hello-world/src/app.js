const express = require("express");
const app = express();
const port = process.env.PORT || 3000;

app.get("/", (_req, res) => {
  res.json({
    message: "HI ZINNN ILUUU",
    hostname: require("os").hostname(),
    version: "2.0.0",
    timestamp: new Date().toISOString(),
  });
});

app.get("/health", (_req, res) => {
  res.status(200).json({ status: "healthy" });
});

app.listen(port, () => {
  console.log(`Hello World app listening on port ${port}`);
});
