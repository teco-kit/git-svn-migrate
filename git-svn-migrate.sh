#!/bin/bash

# Copyright 2010-2011 John Albin Wilkins and contributors.
# Copyright 2016 Armando Lüscher.
# Available under the GPL v2 license. See LICENSE.txt.

script=$(basename $0);
dir=$(pwd);

# Set defaults for any optional parameters or arguments.
destination='.';
gitinit_params='';
gitsvn_params='';
git_author='Armando Lüscher <armando@noplanman.ch>';

_git='git';
_echo='echo';

stdout_file="${dir}/log/$(date +%Y%m%d%H%M%S).std.out";
stderr_file="${dir}/log/$(date +%Y%m%d%H%M%S).std.err";

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
USAGE: ${script} --url-file=<filename> --authors-file=<filename> [destination folder]

For more info, see: ${script} --help
EOF_USAGE
);

help=$(cat <<EOF_HELP
NAME
    ${script} - Migrates Subversion repositories to Git

SYNOPSIS
    ${script} [options] [arguments]

DESCRIPTION
    The ${script} utility migrates a list of Subversion
    repositories to Git using the specified authors list. The
    url-file and authors-file parameters are required. The
    destination folder is optional and can be specified as an
    argument or as a named parameter.

    The following options are available:

    -u=<filename>, -u <filename>,
    --url-file=<filename>, --url-file <filename>
        Specify the file containing the Subversion repository list.

    -a=<filename>, -a <filename>,
    --authors-file=<filename>, --authors-file <filename>
        Specify the file containing the authors transformation data.

    [-d=]<folder>, [-d ]<folder>,
    [--destination=]<folder>, [--destination ]<folder>
        The directory where the new Git repositories should be
        saved. Defaults to the current directory.
        This parameter can also be passed without the param flag.

    -i=<filename>, -i <filename>,
    --ignore-file=<filename>, --ignore-file <filename>
        The location of a .gitignore file to add to all repositories.

    -f, --force
        Force repository creation, even if destination folders exist.
        Be sure about this, it can not be undone! You have been warned.

    -q, --quiet
        By default this script is rather verbose since it outputs each revision
        number as it is processed from Subversion. Since conversion can sometimes
        take hours to complete, this output can be useful. However, this option
        will suppress that output.

    --no-metadata
        By default, all converted log messages will include a line starting with
        "git-svn-id:" which makes it easy to track down old references to
        Subversion revision numbers in existing documentation, bug reports and
        archives. Use this option to get rid of that data. See git svn --help for
        a fuller discussion on this option.

    --shared[=(false|true|umask|group|all|world|everybody|0xxx)]
        Specify that the generated git repositories are to be shared amongst
        several users. See git init --help for more info about this option.

    Any additional options are assumed to be git-svn options and will be passed
    along to that utility directly. Some useful git-svn options are:
        --trunk --tags --branches --no-minimize-url
    See git svn --help for more info about its options.

BASIC EXAMPLES
    # Use the long parameter names
    ${script} --url-file=my-repository-list.txt --authors-file=authors-file.txt --destination=/var/git

    # Use short parameter names
    ${script} -u my-repository-list.txt -a authors-file.txt /var/git

SEE ALSO
    git-svn-migrate-nohup.sh
    fetch-svn-authors.sh
    svn-lookup-author.sh
EOF_HELP
);

_date() {
  echo $(date +%d\.%m\.%Y\ %H\:%M\:%S);
}

# Truly quiet git execution. (idea from http://stackoverflow.com/a/8944284)
quiet_git() {
  return $(git "$@" </dev/null >>${stdout_file} 2>>${stderr_file});
}

# Output the "Done!" message after a step has completed.
echo_done() {
  msg="${1:-Done.}";
  echo "   ${msg}" >&2;
  if [[ ${_echo} == "echo" ]]; then
    echo >&2;
  fi
}

# Process parameters.
until [[ -z "$1" ]]; do
  option=$1;
  # Strip off leading '--' or '-'.
  if [[ ${option:0:1} == '-' ]]; then
    flag_delimiter='-';
    if [[ ${option:0:2} == '--' ]]; then
      tmp=${option:2};
      flag_delimiter='--';
    else
      tmp=${option:1};
    fi
  else
    # Any argument given is assumed to be the destination folder.
    tmp="destination=${option}";
  fi
  parameter=${tmp%%=*}; # Extract option's name.
  value=${tmp##*=};     # Extract option's value.
  # If a value is expected, but not specified inside the parameter, grab the next param.
  if [[ ${value} == ${tmp} ]]; then
    if [[ ${2:0:1} == '-' ]]; then
      # The next parameter is a new option, so unset the value.
      value='';
    else
      value=$2;
    fi
  fi

  case ${parameter} in
    u|url-file )      url_file=${value};;
    a|authors-file )  authors_file=${value};;
    d|destination )   destination=${value};;
    i|ignore-file )   ignore_file=${value};;
    f|force )         force=1;;
    q|quiet )         _git="quiet_git"; _echo="echo -n";;
    shared )          if [[ ${value} == '' ]]; then
                        gitinit_params="--shared";
                      else
                        gitinit_params="--shared=${value}";
                      fi
                      ;;

    h|help )          echo "${help}" | less >&2; exit;;

    * ) # Pass any unknown parameters to git-svn directly.
        if [[ ${value} == '' ]]; then
          gitsvn_params="${gitsvn_params} ${flag_delimiter}${parameter}";
        else
          gitsvn_params="${gitsvn_params} ${flag_delimiter}${parameter}=${value}";
        fi;;
  esac

  # Remove the processed parameter.
  shift;
done

# Check for required parameters.
if [[ ${url_file} == '' || ${authors_file} == '' ]]; then
  echo "\n${ts_b}${tc_y}Both URL file and authors file must be specified.${t_res}\n" >&2;
  echo "${usage}" >&2;
  exit 1;
fi
# Check for valid files.
if [[ ! -f ${url_file} ]]; then
  echo "\n${ts_b}${tc_y}Specified URL file \"${url_file}\" does not exist or is not a file.${t_res}\n" >&2;
  echo "${usage}" >&2;
  exit 1;
fi
if [[ ! -f ${authors_file} ]]; then
  echo "\n${ts_b}${tc_y}Specified authors file \"${authors_file}\" does not exist or is not a file.${t_res}\n" >&2;
  echo "${usage}" >&2;
  exit 1;
fi

# Check that we have links to work with.
if [[ $(grep -cvE '^$|^[#;]' "${url_file}") -eq 0 ]]; then
  echo "\n${ts_b}${tc_y}Specified URL file \"${url_file}\" does not contain any repositories URLs.${t_res}\n" >&2;
  echo "${usage}" >&2;
  exit 1;
fi

echo >&2;

# Process each URL in the repository list.
tmp_destination="/tmp/tmp-git-repo-${RANDOM}";
mkdir -p "${destination}";
destination=$(cd "${destination}"; pwd); #Absolute path.

# Ensure temporary repository location is empty.
if [[ -e ${tmp_destination} ]] && [[ ${force} -eq 0 ]]; then
  echo "\n${ts_b}${tc_y}Temporary repository location \"${tmp_destination}\" already exists. Exiting.${t_res}\n" >&2;
  # todo "You may override with --force flag!"
  exit 1;
fi

# http://stackoverflow.com/a/114861
# http://stackoverflow.com/a/114836
# Ignore empty lines and commented lines (with # or ;)
cnt_total=$(grep -vcE '^$|^[#;]' "${url_file}");
cnt_cur=0;
cnt_pass=0;
cnt_skip=0;
cnt_fail=0;

while IFS= read -r line
do
  ((cnt_cur++));

  skipping=0;
  failing=0;

  # Check for 2-field format:  Name [tab] URL
  name=$(echo ${line} | awk '{print $1}');
  url=$(echo ${line} | awk '{print $2}');

  # Check for simple 1-field format:  URL
  if [[ ${url} == '' ]]; then
    url=${name};
    name=$(basename ${url});
  fi

  # The directory where the new git repository is going.
  destination_git="${destination}/${name}.git";

  # Process each Subversion URL.
  echo "${ts_bu}[${cnt_cur}/${cnt_total}] Processing \"${name}\"${t_res}: $(_date)" >&2;
  echo >&2;
  #echo "Processing ${ts_b}\"${name}\"${t_res} repository:" >&2;
  echo " <  ${url}" >&2;
  echo " >  ${destination_git}" >&2;
  echo >&2;

  # Init the final bare repository.
  # Ensure temporary repository location is empty.
  if [[ -e "${destination_git}" ]] && [[ ${force} -eq 0 ]]; then
    echo " - Repository location \"${destination_git}\" already exists.   Skipped." >&2;
    skipping=1;
  fi

  if [[ ${skipping} -eq 0 ]]; then
    mkdir -p "${destination_git}";
    cd "${destination_git}";
    ${_git} init --bare ${gitinit_params} ${gitsvn_params};
    ${_git} symbolic-ref HEAD refs/heads/trunk ${gitsvn_params};

    # Clone the original Subversion repository to a temp repository.
    cd "${dir}";
    ${_echo} " - Cloning repository..." >&2;
    ${_git} svn clone "${url}" -A "${authors_file}" --authors-prog="${dir}/svn-lookup-author.sh" --stdlayout --quiet "${tmp_destination}" ${gitsvn_params};
    if [[ $? -eq 0 ]]; then
      echo_done;
    else
      skipping=1;
      failing=1;
      echo_done "Failed.";
    fi
  fi

  if [[ ${skipping} -eq 0 ]]; then
    # Create .gitignore file.
    ${_echo} " - svn:ignore => .gitignore file..." >&2;
    if [[ ${ignore_file} != '' ]]; then
      cp "${ignore_file}" "${tmp_destination}/.gitignore";
    fi
    cd "${tmp_destination}";
    ${_git} svn show-ignore --id trunk >> .gitignore;
    ${_git} add .gitignore;
    ${_git} commit --author="${git_author}" -m 'Convert svn:ignore properties to .gitignore.' ${gitsvn_params};
    #git commit --author="git-svn-migrate <nobody@example.org>" -m 'Convert svn:ignore properties to .gitignore.';
    echo_done;

    # Push to final bare repository and remove temp repository.
    ${_echo} " - Pushing to new bare repository..." >&2;
    ${_git} remote add bare "${destination_git}";
    ${_git} config remote.bare.push 'refs/remotes/*:refs/heads/*';
    ${_git} push bare ${gitsvn_params};
    # Push the .gitignore commit that resides on master.
    ${_git} push bare master:trunk ${gitsvn_params};
    cd "${dir}";
    rm -r "${tmp_destination}";
    echo_done;

    ${_echo} " - Fix branches..." >&2;
    # Rename Subversion's "trunk" branch to Git's standard "master" branch.
    cd "${destination_git}";
    ${_git} branch -m trunk master;
    # Remove bogus branches of the form "name@REV".
    ${_git} for-each-ref --format='%(refname)' refs/heads | grep '@[0-9][0-9]*' | cut -d / -f 3- |
    while read ref
    do
      ${_git} branch -D "${ref}";
    done
    echo_done;

    # Convert git-svn tag branches to proper tags.
    ${_echo} " - SVN tags => git tags..." >&2;
    ${_git} for-each-ref --format='%(refname)' refs/heads/tags | cut -d / -f 4 |
    while read ref
    do
      ${_git} tag -a "${ref}" -m "Convert \"${ref}\" to a proper git tag." "refs/heads/tags/${ref}";
      ${_git} branch -D "tags/${ref}";
    done
    echo_done;
    echo >&2;

    echo "[${ts_b}${tc_g}pass${t_res}] $(_date)" >&2;
    ((cnt_pass++));
  else
    echo >&2;
    if [[ ${failing} -ne 0 ]]; then
      echo "[${ts_b}${tc_r}fail${t_res}] $(_date)" >&2;
      ((cnt_fail++));
    else
      echo "[${ts_b}${tc_c}skip${t_res}] $(_date)" >&2;
      ((cnt_skip++));
    fi
  fi

  echo >&2;
done < <(grep -vE '^$|^[#;]' "${url_file}" | nl -w14 -nrz -s, | sort -t, -k2 -u | sort -n | cut -d, -f2-)
# http://stackoverflow.com/a/8197412
# http://mywiki.wooledge.org/BashFAQ/024 (ProcessSubstitution)

echo >&2;
echo "${ts_bu}All done!${t_res}" >&2;
echo "Total:   ${ts_b}${cnt_total}${t_res}" >&2;
echo "Passed:  ${ts_b}${tc_g}${cnt_pass}${t_res}" >&2;
echo "Failed:  ${ts_b}${tc_r}${cnt_fail}${t_res}" >&2;
echo "Skipped: ${ts_b}${tc_c}${cnt_skip}${t_res}" >&2;
echo "Ignored: ${ts_b}${tc_s}$((cnt_total - cnt_cur))${t_res}" >&2
echo >&2;
if [[ $((cnt_skip + cnt_fail)) -ne 0 ]]; then
  echo "(Check the output and logs)" >&2
  echo >&2;
fi
