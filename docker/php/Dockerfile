FROM php:8.3-fpm-bookworm

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        git \
        unzip \
        zip \
        libzip-dev \
        libicu-dev \
        libxslt1-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libxpm-dev \
        libmagickwand-dev \
        libonig-dev \
        libxml2-dev \
        libssl-dev \
        libcurl4-openssl-dev \
        libkrb5-dev \
        librabbitmq-dev \
        libssh-dev \
        libgmp-dev \
        default-mysql-client \
        netcat-openbsd \
        procps \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp --with-xpm \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        exif \
        ftp \
        gd \
        gettext \
        gmp \
        intl \
        opcache \
        pcntl \
        pdo_mysql \
        soap \
        sockets \
        xsl \
        zip \
    && pecl install redis imagick amqp \
    && docker-php-ext-enable redis imagick amqp \
    && curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/php/php.ini /usr/local/etc/php/conf.d/zz-magento.ini
COPY docker/php/zz-docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf
COPY docker/php/entrypoint.sh /usr/local/bin/magento-entrypoint
COPY docker/php/cron.sh /usr/local/bin/magento-cron

RUN chmod +x /usr/local/bin/magento-entrypoint /usr/local/bin/magento-cron

ENTRYPOINT ["/usr/local/bin/magento-entrypoint"]
CMD ["php-fpm", "-F", "-R"]
