#!/bin/bash
filename=${1:-"OPW-CA"}
pfxfile="${filename}.pfx"
keystorefile="${filename}-KEYSTORE.pem"
privatefile="${filename}-PRIVATE.pem"
certonlyfile="${filename}-CERTONLY.pem"

openssl pkcs12 -in $pfxfile -out $keystorefile -nodes 
openssl pkcs12 -in $pfxfile -out $privatefile -nodes -nocerts
openssl pkcs12 -in $pfxfile -out $certonlyfile -nodes -nokeys

