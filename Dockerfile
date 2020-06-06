FROM alpine:3.11

# Inspired by https://github.com/dockage/alpine

LABEL maintainer="qs5779@metaorg.com"

VOLUME /var/log/mail
VOLUME /var/spool/postfix

ENV WTFMAIL_USER = butler
ENV WTFMAIL_USER_PASSWORD = butler
ENV WTFMAIL_HOSTNAME = mail.example.com
ENV WTFMAIL_CERT_DIR = /var/docker/ssl

RUN echo '@edge http://dl-cdn.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories \
    && echo '@edgecommunity http://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories \
    && echo '@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories \
    && apk add --no-cache openrc su-exec ca-certificates wait4ports \
    && apk add --no-cache --update postfix cyrus-sasl cyrus-sasl-plain \
    && apk add --no-cache --upgrade dovecot syslog-ng busybox-initscripts logrotate \
    # Clean up
    # Disable getty's
    && sed -i 's/^\(tty\d\:\:\)/#\1/g' /etc/inittab \
    && sed -i \
        # Change subsystem type to "docker"
        -e 's/#rc_sys=".*"/rc_sys="docker"/g' \
        # Allow all variables through
        -e 's/#rc_env_allow=".*"/rc_env_allow="\*"/g' \
        # Start crashed services
        -e 's/#rc_crashed_stop=.*/rc_crashed_stop=NO/g' \
        -e 's/#rc_crashed_start=.*/rc_crashed_start=YES/g' \
        # Define extra dependencies for services
        -e 's/#rc_provide=".*"/rc_provide="loopback net"/g' \
        /etc/rc.conf \
    # Remove unnecessary services
    && rm -f /etc/init.d/hwdrivers \
            /etc/init.d/hwclock \
            /etc/init.d/hwdrivers \
            /etc/init.d/modules \
            /etc/init.d/modules-load \
            /etc/init.d/modloop \
    # Can't do cgroups
    && sed -i 's/\tcgroup_add_service/\t#cgroup_add_service/g' /lib/rc/sh/openrc-run.sh \
    && sed -i 's/VSERVER/DOCKER/Ig' /lib/rc/sh/init.sh

  RUN rc-update add postfix default \
    && rc-update add dovecot default \
    && rc-update add syslog-ng default \
    && rc-update add crond default \
    && sed -i 's/\/var\/log\/mail/\/var\/log\/mail\/mail/' /etc/syslog-ng/syslog-ng.conf \
    && mv /var/log/mail.log /var/log/mail/mail.log

EXPOSE 25/tcp 143/tcp 587/tcp 993/tcp

# Configure on startup
COPY entrypoint.sh /usr/local/bin/
ENTRYPOINT ["entrypoint.sh"]

CMD ["/sbin/init"]
