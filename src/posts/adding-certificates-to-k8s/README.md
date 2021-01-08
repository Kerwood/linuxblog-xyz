---
title: Converting and adding certificates to Kubernetes
date: 2020-10-20 12:38:05
author: Patrick Kerwood
excerpt: This is a quick tutorial on converting a PFX or PEM certificate to a key/crt pair and deploy it in Kubernetes as a TLS secret.
type: post
blog: true
tags: [kubernetes, certificate]
---

Some times you got to add a static certificate to Kubernetes, the good old fashioned way. I had to do it the other day and I figured I'd document the steps needed. My Security team, who issued the certificate, delivered it as an encrypted PFX file.

The plan is to decrypt, convert to PEM, split it into `key`/`crt` files and deploy it to Kubernetes.

You will need `openssl` to get the job done.

## Decrypt and convert the certificate
First step is to decrypt and convert to PEM. This is the step where you are asked for the encryption password.
```
openssl pkcs12 -in example-org.pfx -out example-org.pem -nodes
```

Extract the private key.
```
openssl pkey -in example-org.pem -out example-org.key
```

Extract the certificate. This file can include multiple certificates, no worries, it's just the certificate chain.
```
openssl crl2pkcs7 -nocrl -certfile example-org.pem | openssl pkcs7 -print_certs -out example-org.crt
```

You should now have a the private key and the certificate in two different files.

## Deploy secret
Deploy the key and certificate to Kubernetes as a secret.
```
kubectl create secret tls <secret-name> --key example-org.key --cert example-org.crt
```

Or if you are replacing an existing TLS secret/certificate, you can update the secret with below command.
```
kubectl create secret tls <secret-name> --key example-org.key --cert example-org.crt --dry-run=client -o yaml | kubectl apply -f -
```

## Verify the certificate
If you are using the certificate on an ingress, it should automatically use the new certificate.

You can verify the certificate with below command.
```
echo | openssl s_client -showcerts -servername example.org -connect example.org:443 2>/dev/null | openssl x509 -inform pem -noout -text
``` 
---