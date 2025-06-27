# Use a lightweight Node.js image
FROM node:18-alpine

# Copy application code to /app
COPY . /app

# Set working directory
WORKDIR /app

# Install dependencies
RUN npm install

# Expose app port (adjust if different)
EXPOSE 5000

# Start the application
CMD ["node", "index.js"]

