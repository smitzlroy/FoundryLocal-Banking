# Multi-stage build for the Next.js edge dashboard (standalone output).
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
# Capture build output to a log and only echo it on failure. This keeps the
# Next.js "▲" logo (a non-cp1252 char) out of the ACR log stream, which crashes
# the Azure CLI's colorama log writer on Windows (az runs python with -I, so
# PYTHONUTF8/PYTHONIOENCODING cannot fix it).
RUN sh -c 'npm run build > /tmp/build.log 2>&1 || (cat /tmp/build.log; exit 1)'

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
