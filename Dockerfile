FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN npm ci --omit=dev

# Copy source code
COPY tsconfig.json ./
COPY src/ ./src/

# Build TypeScript
RUN npm run build

# Copy .env.example as reference (user must provide .env at runtime)
COPY .env.example .env.example

# Expose no ports (MCP stdio transport)
# Health check not applicable for stdio-based MCP server

# Run the MCP server
CMD ["node", "dist/index.js"]
