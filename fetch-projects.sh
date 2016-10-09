 #!/bin/bash
script=$(basename $0);

[ $# > 0 ] || { cat <<EOF_USAGE
USAGE: ${script} <svnurl> <targeturl>
EOF_USAGE
exit 1;}

svn list -R $1 |\
grep 'trunk/$'|\
grep -v branches|\
grep -v tags|\
sed -n \
-e 's#^\(.*\)/\([^/]*\)/trunk/$#\2 '$1'/\1/\2 '$2'/\L\1/\L\2.git#p' \
-e 's#^\([^/]*\)/trunk/$#\1 '$1'/\1 '$2'/\L\1.git#p' 
