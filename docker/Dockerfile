# syntax=docker/dockerfile:1.7
#
# IntelliPilot frontend image. Expects a pre-built Flutter web bundle in
# ./build/web at build context root — the release workflow runs
# `flutter build web --release` first and then invokes `docker buildx build`.
#
# Building the bundle outside Docker keeps this image small, lets us reuse
# the same artifact for the GitHub Release tarball, and produces a multi-arch
# manifest with one buildx invocation (only the nginx base layer is
# arch-specific; the bundle itself is portable).

FROM nginx:1.27-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
EXPOSE 80
