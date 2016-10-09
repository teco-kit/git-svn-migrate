#!/bin/bash
script=$(basename $0);

[ $# = 2 ] || { cat <<EOF_USAGE
USAGE: ${script} <url_file> <base_dir>
EOF_USAGE

exit 1;}

url_file=$1
destination=$2
mkdir -p ${destination}/pushed 

while IFS= read -r line
do
  name=$(echo ${line} | awk '{print $1}');
  url=$(echo ${line} | awk '{print $2}');
  remote=$(echo ${line} | awk '{print $3}');

[ -d ${destination}/${name}.git ] &&
git -C ${destination}/${name}.git push --all ${remote} &&\
svn rm -m "moved to ${remote}" $url &&\
mv ${destination}/${name}.git ${destination}/pushed 


done < <(grep -vE '^$|^[#;]' "${url_file}" | nl -w14 -nrz -s, | sort -t, -k2 -u | sort -n | cut -d, -f2-)
