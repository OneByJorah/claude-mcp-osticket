FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies (include dev for the tsc build step)
RUN npm ci

# Copy source code
COPY tsconfig.json ./
COPY src/ ./src/

# Build TypeScript
RUN npm run build

# Prune dev dependencies for a leaner runtime image
RUN npm prune --omit=dev

# Copy .env.example as reference (user must provide .env at runtime)
COPY .env.example .env.example

# Expose no ports (MCP stdio transport)
# Health check not applicable for stdio-based MCP server

# Run the MCP server
CMD ["node", "dist/index.js"]
