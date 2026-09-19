FROM node:20-alpine
WORKDIR /usr/src/app
COPY package.json ./
RUN npm install --omit=dev
COPY client.js ./
ENV SERVER_URL=http://server:3000
ENV SIM_MAX=30
CMD ["node", "client.js"]