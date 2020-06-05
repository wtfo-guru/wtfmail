WTFMAIL# Docker image wtfmail

I have given up trying to reliably collect email from my servers in an
external account.

This image brings up a postfix server with no spam / content filtering, as
it is not intended to be available from the external WAN.

This is not release ready. Still under development.

# ENVIRONMENT VARIABLES

|Name|Default|Description|
|---|---|---|
|WTFMAIL_USER|butler|All mail goes to a single user.|
|WTFMAIL_USER_PASSWORD|butler||
|WTFMAIL_HOSTNAME|mail.example.com|hostname (should match server cert if used)|
|WTFMAIL_CERT_DIR||Bind mounted volume were specified certs will be|
|WTFMAIL_CA_CERTS||list of ca certs to use|
|WTFMAIL_SERVER_CERT||a single chain cert containing in order, key,cert,<optional chain>,<optional ca>|
|WTFMAIL_CLIENT_CERT|||
