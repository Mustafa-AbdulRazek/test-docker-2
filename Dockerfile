# Use official Nginx image
FROM nginx:alpine

# Remove default nginx index.html
RUN rm -rf /usr/share/nginx/html/*

# Copy project files
COPY . /usr/share/nginx/html

# Expose port 80
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
