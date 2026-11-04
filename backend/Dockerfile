# API IaHope Gestão — Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
RUN mkdir -p uploads && chown node:node uploads
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
