 #!/bin/bash
script=$(basename $0);

[ $# == 2 ] || { cat <<EOF_USAGE
USAGE: ${script} <ldapserver> <base> 
EOF_USAGE
exit 1;}

 ldapsearch -LLL -x -H ldap://$1 -b $2  uid cn mail|\
 awk -F': ' '
 /^cn: .* .+$/{cn=$2;next} 
 /^cn.*=$/{"echo "$2"|base64 -d"|getline x;cn=x} 
 /mail/{mail=$2} 
 /^uid/{uid=$2} 
 /^dn/{print uid"=" cn " <"mail">"}'
