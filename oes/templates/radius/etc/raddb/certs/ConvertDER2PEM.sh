#!/bin/bash
filename=${1:-"OPW-CA"}
derfile="${filename}.der"
pemfile="${filename}.pem"

openssl x509 -inform der -in $derfile -out $pemfile
