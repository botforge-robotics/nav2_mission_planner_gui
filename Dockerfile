# Serve prebuilt Flutter web (run locally: flutter build web --release --no-tree-shake-icons)
# Keeps Docker image small and avoids pulling a Flutter SDK image.
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
