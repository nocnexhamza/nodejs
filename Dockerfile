FROM node:18-alpine

RUN mkdir -p /app
COPY . /app

RUN cd /app && npm install

EXPOSE 5000
CMD ["node", "/app/index.js"]
