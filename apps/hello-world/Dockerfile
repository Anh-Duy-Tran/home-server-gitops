FROM node:18-alpine

WORKDIR /usr/src/app

# Copy package files
COPY src/package*.json ./

# Install dependencies
RUN npm install --omit=dev

# Copy application code
COPY src/ ./

# Expose port
EXPOSE 3000

# Run as non-root user
USER node

# Start the application
CMD ["node", "app.js"]