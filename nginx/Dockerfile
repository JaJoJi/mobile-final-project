# checkov:skip=CKV_DOCKER_3:nginx needs root to bind port 80; the base
# image's own nginx.conf already drops worker processes to the unprivileged
# `nginx` user internally (`user nginx;`) — standard nginx privilege-drop
# behavior, not something an extra USER line here would change.
FROM nginx:1.27-alpine
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost/health || exit 1
CMD ["nginx", "-g", "daemon off;"]
