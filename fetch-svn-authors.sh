#!/bin/bash

# Copyright 2010 John Albin Wilkins.
# Copyright 2016 Armando Lüscher.
# Available under the GPL v2 license. See LICENSE.txt.

script=$(basename $0);
dir=$(pwd);

# Set defaults for any optional parameters or arguments.
destination=''; # Must be a valid path, empty value outputs to the screen only.

# Text style and color variables.
ts_u=$(tput sgr 0 1); # underline
ts_b=$(tput bold);    # bold
ts_bu=${ts_u}${ts_b}; # bold & underline
t_res=$(tput sgr0);   # reset
tc_r=$(tput setaf 1); # red
tc_g=$(tput setaf 2); # green
tc_y=$(tput setaf 3); # yellow
tc_p=$(tput setaf 4); # purple
tc_v=$(tput setaf 5); # violet
tc_c=$(tput setaf 6); # cyan
tc_w=$(tput setaf 7); # white
tc_s=$(tput setaf 8); # silver

usage=$(cat <<EOF_USAGE
USAGE: ${script} --url-file=<filename> [destination filename]

For more info, see: ${script} --help
EOF_USAGE
);

help=$(cat <<EOF_HELP
NAME
    ${script} - Retrieves Subversion usernames from a list of
    URLs for use in a git-svn-migrate (or git-svn) conversion.

SYNOPSIS
    ${script} [options] [arguments]

DESCRIPTION
    The ${script} utility creates a list of Subversion committers
    from a list of Subversion URLs for Git using the
    specified authors list. The url-file parameter is required.
    The destination parameter is optional and can be specified as an
    argument or as a named parameter. If it is not specified the authors
    will be displayed in standard output.

    The following options are required:

    -u=<filename>, -u <filename>,
    --url-file=<filename>, --url-file <filename>
        Specify the file containing the Subversion repository list.

    The following options are available:

    [-d=]<file>, [-d ]<file>,
    [--destination=]<file>, [--destination ]<file>
        The file where the exported list of authors be saved.
        (Defaults to the display directly in standard output.)

    -f, --force
        Force destination file creation, even if it already exists.
        Be sure about this, it can not be undone! You have been warned.

    -h, --help
        Display this help message.

BASIC EXAMPLES
    # Use the long parameter names
    ${script} --url-file=my-repository-list.txt --destination=authors-file.txt

    # Use short parameter names and redirect standard output
    ${script} -u my-repository-list.txt > authors-file.txt
    ${script} -u my-repository-list.txt authors-file.txt

SEE ALSO
    git-svn-migrate-nohup.sh
    git-svn-migrate.sh
    svn-lookup-author.sh
EOF_HELP
);

# Destination to get from parameters.
destination_param='';

# Process parameters.
until [[ -z "$1" ]]; do
  option=$1;
  # Strip off leading '--' or '-'.
  if [[ ${option:0:1} == '-' ]]; then
    if [[ ${option:0:2} == '--' ]]; then
      tmp=${option:2};
    else
      tmp=${option:1};
    fi
  else
    # Any argument given is assumed to be the destination folder.
    tmp="destination=${option}";
  fi
  parameter=${tmp%%=*}; # Extract option's name.
  value=${tmp##*=};     # Extract option's value.
  case ${parameter} in
    # Some parameters don't require a value.
    #no-minimize-url ) ;;

    # If a value is expected, but not specified inside the parameter, grab the next param.
    * )
      if [[ ${value} == ${tmp} ]]; then
        if [[ ${2:0:1} == '-' ]]; then
          # The next parameter is a new option, so unset the value.
          value='';
        else
          value=$2;
          shift;
        fi
      fi
      ;;
  esac

  case ${parameter} in
    u|url-file )     url_file=${value};;
    d|destination )  # empty, ".", and ".." are invalid.
                     if [[ ! ${value} =~ ^\.?\.?$ ]]; then
                       destination_param=${destination_param:-$value}
                     fi
                     ;;
    f|force )        force=1;;

    h|help )         echo "${help}" | less >&2; exit;;

    * )              echo -e "\n${ts_b}${tc_y}Unknown option: ${option}${t_res}\n\n${usage}" >&2;
                     exit 1;
                     ;;
  esac

  # Remove the processed parameter.
  shift;
done

# Set the definite destination.
destination=${destination_param:-$destination};

# If a valid destination is given, make it a full path.
if [[ ! ${destination} =~ ^\.?\.?$ ]]; then destination="${dir}/${destination}"; else destination=''; fi

# Check for required parameters.
if [[ ${url_file} == '' ]]; then
  echo -e "\n${ts_b}${tc_y}No URL file specified.${t_res}\n" >&2;
  echo "${usage}" >&2;
  exit 1;
fi

# Check for valid file.
if [[ ! -f ${url_file} ]]; then
  echo -e "\n${ts_b}${tc_y}Specified URL file \"${url_file}\" does not exist or is not a file.${t_res}\n" >&2;
  echo "${usage}" >&2;
  exit 1;
fi

# Check that we have links to work with.
if [[ $(grep -cvE '^$|^[#;]' "${url_file}") -eq 0 ]]; then
  echo -e "\n${ts_b}${tc_y}Specified URL file \"${url_file}\" does not contain any repositories URLs.${t_res}\n" >&2;
  echo "${usage}" >&2;
  exit 1;
fi

# Ensure output file doesn't exist, or force overwrite.
if [[ -e ${destination} ]] && [[ ${force} -eq 0 ]]; then
  echo -e "\n${ts_b}${tc_y}Destination location \"${destination}\" already exists. Exiting.${t_res}\n" >&2;
  echo "You may override this with the \"--force\" flag." >&2;
  exit 1;
fi

echo >&2;

# Process each URL in the repository list.
tmp_file="/tmp/tmp-authors-transform-${RANDOM}";
while IFS= read -r line
do
  # Check for 2-field format:  Name [tab] URL
  name=$(echo ${line} | awk '{print $1}');
  url=$(echo ${line} | awk '{print $2}');
  # Check for simple 1-field format:  URL
  if [[ ${url} == '' ]]; then
    url=${name};
    name=$(basename ${url});
  fi
  # Process the log of each Subversion URL.
  echo -n "Processing ${ts_b}\"${name}\"${t_res} repository at ${url}" >&2;
  res=$(svn log -q "${url}" 2>&1);
  if [[ $? -eq 0 ]]; then
    echo "${res}" | awk -F '|' '/^r/ {sub("^ ", "", $2); sub(" $", "", $2); print $2" = "$2" <"$2">"}' | sort -u >> ${tmp_file};
    echo "   ${ts_b}${tc_g}Done.${t_res}" >&2;
  else
    echo "   ${ts_b}${tc_r}Failed.${t_res}" >&2;
    #echo -e "${ts_b}${tc_r}${res}${t_res}\n" >&2;
  fi
done < <(grep -vE '^$|^[#;]' "${url_file}" | nl -w14 -nrz -s, | sort -t, -k2 -u | sort -n | cut -d, -f2-)
# Unique entries: http://stackoverflow.com/a/30906433

echo >&2;

echo -n "${ts_bu}Authors list${t_res}" >&2;

# Do we have any valid entries?
if [[ ! -f ${tmp_file} ]]; then
  echo -e "\n${ts_b}${tc_y}No Authors found.${t_res}\n" >&2;
  exit 1;
fi

# Sort unique lines.
cat ${tmp_file} | sort -u -o ${tmp_file};

# Process temp file one last time to show results.
if [[ ${destination} == '' ]]; then
  echo >&2;
  # Display on standard output.
  cat ${tmp_file};
else
  # Copy to the specified destination file.
  cp ${tmp_file} ${destination};
  echo " saved to: ${destination}" >&2;
fi

unlink ${tmp_file};

echo >&2;
