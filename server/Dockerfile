FROM node:20-alpine AS builder

WORKDIR /usr/src/app

COPY package.json package-lock.json* ./
RUN npm install

COPY tsconfig.json ./
COPY src ./src
COPY tools ./tools
COPY agent-release ./agent-release

RUN npm run build

FROM node:20-alpine AS runtime

WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/dist ./dist
COPY --from=builder /usr/src/app/tools ./tools
COPY --from=builder /usr/src/app/agent-release ./agent-release
COPY --from=builder /usr/src/app/package.json ./

RUN npm install --production --ignore-scripts

COPY .env* ./

EXPOSE 3000

CMD ["node", "dist/index.js"]