svn list -R $1 |grep 'trunk/$'|grep -v branches|grep -v tags|sed -n -e 's#^\(.*\)/\([^/]*\)/trunk/$#\2 '$1'/\1/\2#p' -e 's#^\([^/]*\)/trunk/$#\1 '$1'/\1#p' 
