#!/bin/bash
set -euo pipefail
rm -f exampleca.* example.* cert.h private_key.h

# ------------------------------
# Create a real CA (with CA:TRUE) using 4096-bit key
openssl genrsa -out exampleca.key 4096

cat > exampleca.conf << 'EOF'
[ req ]
prompt                 = no
distinguished_name     = dn
x509_extensions        = v3_ca

[ dn ]
C  = DE
ST = BE
L  = Berlin
O  = MyCompany
CN = myca.local

[ v3_ca ]
basicConstraints       = critical, CA:true, pathlen:0
keyUsage               = critical, keyCertSign, cRLSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

openssl req -new -x509 -days 3650 -sha256 \
  -key exampleca.key -out exampleca.crt -config exampleca.conf

# Create serial file automatically (or let -CAcreateserial do it)
echo "01" > exampleca.srl

# ------------------------------
# Create server key + CSR with proper extensions + SAN
openssl genrsa -out example.key 1024

cat > example.conf << 'EOF'
[ req ]
prompt             = no
distinguished_name = dn
req_extensions     = v3_req

[ dn ]
C  = DE
ST = BE
L  = Berlin
O  = MyCompany
CN = esp32.local

[ v3_req ]
basicConstraints   = CA:false
keyUsage           = critical, digitalSignature, keyEncipherment
extendedKeyUsage   = serverAuth, clientAuth
subjectAltName     = @alt_names

[ alt_names ]
DNS.1 = esp32.local
DNS.2 = myesp
EOF

openssl req -new -sha256 -key example.key -out example.csr -config example.conf

# Sign leaf cert with the CA, carrying over the server extensions
openssl x509 -req -days 3650 -sha256 \
  -in example.csr -CA exampleca.crt -CAkey exampleca.key \
  -CAserial exampleca.srl \
  -extfile example.conf -extensions v3_req \
  -out example.crt

echo "-- verifying openssl certificate now ---"
openssl verify -CAfile exampleca.crt example.crt

echo "--- verifying openssl certificate finished ---"

# convert private key and certificate into DER format
openssl rsa -in example.key -outform DER -out example.key.DER
openssl x509 -in example.crt -outform DER -out example.crt.DER

# create header files
echo "#ifndef CERT_H_" > ./cert.h
echo "#define CERT_H_" >> ./cert.h
xxd -i example.crt.DER >> ./cert.h
echo "#endif" >> ./cert.h

echo "#ifndef PRIVATE_KEY_H_" > ./private_key.h
echo "#define PRIVATE_KEY_H_" >> ./private_key.h
xxd -i example.key.DER >> ./private_key.h
echo "#endif" >> ./private_key.h

# Copy files to every example
for D in ../examples/*; do
  if [ -d "${D}" ] && [ -f "${D}/$(basename $D).ino" ]; then
    echo "Adding certificate to example $(basename $D)"
    cp ./cert.h ./private_key.h "${D}/"
  fi
done

echo ""
echo "Certificates created!"
echo "---------------------"
echo ""
echo "  Private key:      private_key.h"
echo "  Certificate data: cert.h"
echo ""
echo "Make sure to have both files available for inclusion when running the examples."
echo "The files have been copied to all example directories, so if you open an example"
echo " sketch, you should be fine."
