---
title: Signing a Certificate with a CA
date: 2023-04-14 12:38:05
author: Patrick Kerwood
excerpt: In this post I will use OpenSSL to create a Certificate Authority key pair, a certificate private key with a Certificate Signing Request with Subject Alternate Names and lastly I will sign the CSR with the CA.
type: post
blog: true
tags: [openssl, certificate]
meta:
- name: description
  content: How to sign a certificate with a CA using OpenSSL
---
{{ $frontmatter.excerpt }}


Create a CA private key, this will create a file named `ca.key`.
``` 
openssl genrsa -out ca.key 4096
```

Create a configuration file for the CA.
Change the `[ dn ]` block to fit your needs, or just delete all lines except the `commonName`.
```
cat << EOF > ca-config.txt
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn 
x509_extensions = v3_ca

[ dn ]
commonName             = "root.your-domain.com"     # CN=
countryName            = "DK"                       # C=
stateOrProvinceName    = "Some Province"            # ST=
localityName           = "Some Name"                # L=
postalCode             = "12345"                    # L/postalcode=
streetAddress          = "Some Streetname"          # L/street=
organizationName       = "Some Org"                 # O=
organizationalUnitName = "Some OU"                  # OU=
emailAddress           = "email@example.org"        # CN/emailAddress=

[ v3_ca ]
basicConstraints=CA:TRUE
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer 
EOF
```

Create the CA cert, below example makes it expire in 10 years.
```
openssl req -new -x509 -key ca.key -out ca.crt -days 3650 -config ca-config.txt
```

Create a configuration for the certificate with the needed SANs.
```
cat << EOF > example-org-config.txt
[req]
default_bits = 4096
prompt = no
default_md = sha256
x509_extensions = req_ext
req_extensions = req_ext
distinguished_name = dn
 
[ dn ]
CN = example.org
 
[ req_ext ]
subjectAltName = @alt_names
 
[ alt_names ]
DNS.1 = example.org
DNS.2 = www.example.org
DNS.3 = some-other.example.org
EOF
```

Create a private certificate key and a Certificate Signing Request.
```
openssl req -newkey rsa:2048 -keyout tls.key -out example-org.csr -config example-org-config.txt -nodes
```

::: details If you have an existing private key you want to use, instead of creating one, see this example.
Create a Certificate Signing Request with an existing private key.
```
openssl req -new -key tls.key -out example-org.csr -config example-org-config.txt 
```
:::

Create the certificate from the signing request and the CA.
```
openssl x509 -req -in example-org.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out tls.crt -days 3650 -extensions 'req_ext' -extfile example-org-config.txt
```

You should now have the following files.
- `ca.crt`
- `ca.key`
- `tls.crt`
- `tls.key`

## Check certificate information
If you need to see the contents from the differnet files you can use these commands.

Check the Certificate Signing Request.
```
openssl req -text -noout -verify -in example-org.csr
```

Check the Private Key.
```
openssl rsa -in tls.key -check
```

Check the Certificate.
```
openssl x509 -in tls.crt -text -noout
```

