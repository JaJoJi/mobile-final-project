# checkov:skip=CKV_DOCKER_3: the nginx master process must start as root to bind :80 and drops workers to the `nginx` user itself; this image is replaced by the non-root ModSecurity image (listens on 8080) in #224.
FROM nginx:1.27-alpine
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://127.0.0.1/health || exit 1
CMD ["nginx", "-g", "daemon off;"]
