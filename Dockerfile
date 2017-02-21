FROM phusion/baseimage:0.9.19

MAINTAINER Giorgio Aresu <giorgioaresu@gmail.com>

ENV TZ Europe/Rome

VOLUME ["/config"]
EXPOSE 80

WORKDIR /tmp

ARG DEBIAN_FRONTEND=noninteractive

CMD ["/sbin/my_init"]

RUN \
# Set timezone (see https://bugs.launchpad.net/ubuntu/+source/tzdata/+bug/1554806)
    ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime && \
    dpkg-reconfigure --frontend noninteractive tzdata

RUN \
# Update base image
    apt-get update && apt-get upgrade -y -o Dpkg::Options::="--force-confold"

RUN \
# Update and install packages
    apt-get update && \
    apt-get install -y \
        apache2 \
        curl \
        ffmpeg \
        gdebi-core \
        git \
        libapache2-mod-php \
        libav-tools \
        mysql-server \
        php \
        php-gd \
        sudo \
        wget \
    && \

# Compile zoneminder from source and install it
    wget https://raw.githubusercontent.com/ZoneMinder/ZoneMinder/master/utils/do_debian_package.sh && \
    chmod a+x do_debian_package.sh && \
    yes '' | ./do_debian_package.sh `lsb_release -a 2>/dev/null | grep Codename | awk '{print $2}'`  `date +%Y%m%d`01 local feature-h264-videostorage && \
    yes y | gdebi zoneminder_*.deb && \
    # mv zoneminder_*.deb /var/cache/apt/archives/ && apt-get install -y zoneminder && \

# Setup database
    cp --remove-destination /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/my.cnf && \
    sed '/\[mysqld\]/a sql_mode = NO_ENGINE_SUBSTITUTION' /etc/mysql/my.cnf && \
    service mysql restart && \
    mysql -uroot < /usr/share/zoneminder/db/zm_create.sql && \
    mysql -uroot -e "grant select,insert,update,delete,create,alter,index,lock tables on zm.* to 'zmuser'@localhost identified by 'zmpass';" && \
    service mysql restart && \

# Setup Apache
    chmod 740 /etc/zm/zm.conf && \
    chown root:www-data /etc/zm/zm.conf && \
    chown -R www-data:www-data /usr/share/zoneminder/ && \
    a2enconf zoneminder && \
    a2enmod cgi && \
    a2enmod rewrite && \
    sed -i 's#\;date.timezone =#date.timezone = \"${TZ}\"#' /etc/php/7.0/apache2/php.ini && \
    service apache2 restart && \

# Add cambozola
    wget http://www.andywilcock.com/code/cambozola/cambozola-latest.tar.gz && \
    tar -xf cambozola-latest.tar.gz -C /usr/share/zoneminder/www --strip-components=2 --wildcards cambozola*/dist/cambozola.jar && \

# Cleanup
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY zoneminder /etc/init.d/zoneminder
COPY start.sh /etc/init.d/start.sh

RUN chmod +x \
        /etc/init.d/zoneminder \
        /etc/init.d/start.sh \
    && \
    service apache2 restart && \
    update-rc.d -f apache2 remove && \
    update-rc.d -f mysql remove && \
    update-rc.d -f zoneminder remove

HEALTHCHECK --interval=5m --timeout=3s \
    CMD curl -f http://localhost/zm/api/versions.json || exit 1