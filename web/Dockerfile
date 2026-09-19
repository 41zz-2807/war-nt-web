FROM node:20-alpine

WORKDIR /usr/src/app

# Sajikan dashboard statis (tanpa nginx) via Node static server
COPY server.js ./
COPY public ./public

ENV PORT=80
EXPOSE 80

CMD ["node", "server.js"]