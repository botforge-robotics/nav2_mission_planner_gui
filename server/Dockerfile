FROM node:22-bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src
RUN mkdir -p /data
ENV DB_PATH=/data/app.db
ENV API_PORT=3001
EXPOSE 3001
CMD ["npm", "start"]
