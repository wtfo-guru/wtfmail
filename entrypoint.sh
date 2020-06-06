#!/bin/sh

MYHOSTNAME=${WTFMAIL_HOSTNAME:-mail.example.com}
BUTLER=${WTFMAIL_USER:-butler@example.com}
PASSWORD=${WTFMAIL_USER_PASSWORD:-butler}
postconf -e "myhostname=${MYHOSTNAME}"

if [[ -n "$WTFMAIL_DOMAIN" ]]
then
  MYDOMAIN=${WTFMAIL_DOMAIN}
else
  MYDOMAIN=`echo $MYHOSTNAME | cut -d '.' -f 2-`
fi

postconf -e "mydomain=${MYDOMAIN}"
postconf -e "mydestination = localhost.\$mydomain, localhost"
postconf -e "mynetworks_style = subnet"
postconf -e "mynetworks = 127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

VA_MAPS=/etc/postfix/virtual
if [[ -n "$WTFMAIL_VIRTUAL_ALIAS_DOMAINS" ]]
then
  postconf -e "virtual_alias_domains=${WTFMAIL_VIRTUAL_ALIAS_DOMAINS}"
  for VALUE in $(echo "$WTFMAIL_VIRTUAL_ALIAS_DOMAINS" | tr '[,;]' '[ ]')
  do
    sed -r -i "/^@${VALUE} /d" "$VA_MAPS"
    printf "@%-25s @%s\n" "$VALUE" "$MYDOMAIN" >> "$VA_MAPS"
  done
else
  postconf -e "virtual_alias_domains="
fi


if [[ -n "$WTFMAIL_RELAY_HOST" ]]
then
  postconf -e "relayhost = ${WTFMAIL_RELAY_HOST}"
else
  postconf -e "relayhost ="
fi

postconf -e "virtual_mailbox_domains=${MYDOMAIN}"

postconf -e "virtual_alias_maps = hash:${VA_MAPS}"

MBOX_MAPS=/etc/postfix/virtual_mailbox_maps
MBOX_DIR=/var/docker/mail/domains
MBOX_ID=1006

postconf -e "virtual_mailbox_maps = hash:${MBOX_MAPS}"
postconf -e "virtual_mailbox_base = ${MBOX_DIR}"
postconf -e "virtual_gid_maps = static:${MBOX_ID}"
postconf -e "virtual_uid_maps = static:${MBOX_ID}"
postconf -e "virtual_minimum_uid = 100"
postconf -e "virtual_transport = virtual"

[[ -d /var/docker/mail/domains && ! -e /var/mail/domains ]] && ln -s /var/docker/mail/domains /var/mail/domains

# This next command means you must create a virtual
# domain for the host itself - ALL mail goes through
# The virtual transport

postconf -e "mailbox_transport = virtual"
postconf -e "local_transport = virtual"
postconf -e "local_transport_maps = \$virtual_mailbox_maps"

postconf -e "smtpd_helo_required = yes"
postconf -e "disable_vrfy_command = yes"
postconf -e "message_size_limit = 10240000"
postconf -e "queue_minfree = 51200000"

postconf -e "smtpd_sender_restrictions=permit_mynetworks,reject_non_fqdn_sender,reject_unknown_sender_domain"
postconf -e "smtpd_recipient_restrictions=reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination"
#       reject_rbl_client dnsbl.sorbs.net,
#       reject_rbl_client zen.spamhaus.org,
#       reject_rbl_client bl.spamcop.net

postconf -e "smtpd_data_restrictions = reject_unauth_pipelining"

CERT_DIR=${WTFMAIL_CERT_DIR:-/var/docker/ssl}
if [[ -n "$WTFMAIL_CLIENT_CERT" ]]
then
  VALUE="${CERT_DIR}/${WTFMAIL_CLIENT_CERT}"
else
  VALUE=''
fi

if [[ -n "$VALUE" && -f "$VALUE" ]]
then
  postconf -e "smtp_tls_loglevel = 0"
  postconf -e "smtp_tls_chain_files = $VALUE"
  postconf -e "smtp_tls_key_file ="
  postconf -e "smtp_tls_cert_file ="
  postconf -e "smtp_use_tls = yes"
  postconf -e "smtp_tls_mandatory_ciphers = high"
  postconf -e "smtp_tls_security_level = encrypt"
  postconf -e "smtp_tls_session_cache_database = btree:\${data_directory}/smtp_tls_session_cache"
  # TODO: add else to clear them
fi

if [[ -n "$WTFMAIL_SERVER_CERT" ]]
then
  VALUE="${CERT_DIR}/${WTFMAIL_SERVER_CERT}"
else
  VALUE=''
fi

if [[ -n "$VALUE" && -f "$VALUE" ]]
then
  postconf -e "smtpd_tls_loglevel = 0"
  postconf -e "smtpd_tls_auth_only = yes"
  postconf -e "smtpd_tls_chain_files = $VALUE"
  postconf -e "smtpd_tls_key_file ="
  postconf -e "smtpd_tls_cert_file ="
  postconf -e "smtpd_use_tls = yes"
  postconf -e "smtpd_tls_mandatory_ciphers = high"
  postconf -e "smtpd_tls_security_level = may"
  postconf -e "smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_tls_session_cache"
  # TODO: add else to clear them
  DOVECOT_CRT="$VALUE"
  DOVECOT_KEY="$VALUE"
else
  DOVECOT_CRT=/etc/ssl/dovecot/server.pem
  DOVECOT_KEY=/etc/ssl/dovecot/server.key
fi

if [[ -n "$WTFMAIL_CA_CERTS" ]]
then
  for VALUE in $(echo "$WTFMAIL_CA_CERTS" | tr '[,;]' '[ ]')
  do
    TGT=${CERT_DIR}/${VALUE}
    CACERT="/etc/ssl/certs/${VALUE}"
    [[ -e "$CACERT" ]] && rm "$CACERT"
    [[ -f "$TGT" ]] && ln -s "$TGT" "$CACERT"
  done
  update-ca-certificates
  unset CACERT TGT
fi

touch "$MBOX_MAPS"
for entry in ${MYDOMAIN} ${MYHOSTNAME} localhost localhost.localdomain
do
  # delete existing entry
  sed -r -i "/^@${entry} /d" "$MBOX_MAPS"
  printf "@%-25s %s/%s/\n" "$entry" "$MYDOMAIN" "$BUTLER" >> "$MBOX_MAPS"
done

sed -r -i "s/^#root .*/root:		${BUTLER}@${MYDOMAIN}/" /etc/postfix/aliases
postmap "$MBOX_MAPS"
postmap "$VA_MAPS"
newaliases

# Use 587 (submission)
# -r -i 's/^#submission/submission/' /etc/postfix/master.cf

MBOX_DIR="${MBOX_DIR}/${MYDOMAIN}/${BUTLER}"
[[ ! -d "$MBOX_DIR" ]] && mkdir -p "$MBOX_DIR"
chown -R ${MBOX_ID}:${MBOX_ID} "$MBOX_DIR"

DOVECOT_CFG=/etc/dovecot/dovecot.conf

[[ -f "${DOVECOT_CFG}.original" ]] || cp "$DOVECOT_CFG" "${DOVECOT_CFG}.original"

DCPWD=/etc/dovecot/dovecot-passwd
DCUSR=/etc/dovecot/dovecot-users

MBOX_DIR=$(dirname "$MBOX_DIR")
VALUE=$(/usr/bin/doveadm pw -s MD5-CRYPT -p $PASSWORD | sed -e 's/{MD5-CRYPT}//')
printf "%s@%s::%d:%d::%s/:/bin/false::\n" "$BUTLER" $MYDOMAIN $MBOX_ID $MBOX_ID "$MBOX_DIR" > $DCUSR
printf "%s@%s:%s\n" "$BUTLER" $MYDOMAIN "$VALUE" > $DCPWD

cat <<ENDCFG > "$DOVECOT_CFG"
auth_mechanisms = plain login
#auth_username_format = %Lu
auth_verbose = yes
disable_plaintext_auth = no
info_log_path = /var/log/mail/dovecot-info.log
log_path = /var/log/mail/dovecot.log
mail_location = maildir:/var/docker/mail/domains/%d/%n
passdb {
  args = $DCPWD
  driver = passwd-file
}
plugin {
  autocreate = Trash
  autocreate2 = Spam
  autocreate3 = Sent
  autosubscribe = Trash
  autosubscribe2 = Spam
  autosubscribe3 = Sent
}
protocols = imap
# uncomment if you want disable imap on port 143 to enforce imaps
#service imap-login {
#  inet_listener imap {
#    port = 0
#  }
#}
ssl_cert = <${DOVECOT_CRT}
ssl_key = <${DOVECOT_KEY}
userdb {
  args = $DCUSR
  driver = passwd-file
}
protocol imap {
  mail_plugins = autocreate
}
ENDCFG

unset BUTLER MBOX_DIR MBOX_ID MBOX_MAPS VA_MAPS
unset DOVECOT_CRT DOVECOT_KEY DCPWD DCUSR VALUE PASSWORD CERT_DIR

exec "$@"
