# syntax=docker/dockerfile:1

FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-scripts \
    --no-progress \
    --prefer-dist \
    --optimize-autoloader

FROM php:8.3-cli-alpine AS runtime

RUN apk add --no-cache postgresql-dev oniguruma-dev libxml2-dev curl-dev \
    && docker-php-ext-install -j"$(nproc)" pdo pdo_pgsql mbstring xml bcmath curl \
    && apk del postgresql-dev oniguruma-dev libxml2-dev curl-dev \
    && addgroup -g 1000 appuser \
    && adduser -D -u 1000 -G appuser appuser

WORKDIR /var/www/html
COPY --chown=appuser:appuser . .
COPY --from=vendor --chown=appuser:appuser /app/vendor ./vendor

RUN chown -R appuser:appuser storage bootstrap/cache

USER appuser

ARG API_PORT=8080
ENV API_PORT=${API_PORT}
EXPOSE ${API_PORT}

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
    CMD wget --no-verbose --tries=1 --spider "http://127.0.0.1:${API_PORT}/api/v1/health" || exit 1

CMD ["sh", "-c", "php artisan serve --host=0.0.0.0 --port=${API_PORT}"]
