FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN npm ci --include=dev

# Copy source code
COPY tsconfig.json ./
COPY src/ ./src/

# Build TypeScript
RUN npm run build

RUN npm prune --omit=dev

FROM node:18-alpine

WORKDIR /app
COPY --from=builder /app/package.json /app/package-lock.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

# Copy .env.example as reference (user must provide .env at runtime)
COPY .env.example .env.example

# Expose no ports (MCP stdio transport)
# Health check not applicable for stdio-based MCP server

# Run the MCP server
CMD ["node", "dist/index.js"]
