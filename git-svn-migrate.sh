#!/bin/bash

# Copyright 2010-2011 John Albin Wilkins and contributors.
# Available under the GPL v2 license. See LICENSE.txt.

script=`basename $0`;
dir=`pwd`/`dirname $0`;

# Set defaults for any optional parameters or arguments.
destination='.';
gitinit_params='';
gitsvn_params='';
git_author='Armando Lüscher <armando@noplanman.ch>';

git_cmd='git';
printf_cmd='echo';

stdout_file="$dir/log/$(date +%Y%m%d%H%M%S).std.out";
stderr_file="$dir/log/$(date +%Y%m%d%H%M%S).std.err";

usage=$(cat <<EOF_USAGE
USAGE: $script --url-file=<filename> --authors-file=<filename> [destination folder]
\n
\nFor more info, see: $script --help
EOF_USAGE
);

help=$(cat <<EOF_HELP
NAME
\n\t$script - Migrates Subversion repositories to Git
\n
\nSYNOPSIS
\n\t$script [options] [arguments]
\n
\nDESCRIPTION
\n\tThe $script utility migrates a list of Subversion
\n\trepositories to Git using the specified authors list. The
\n\turl-file and authors-file parameters are required. The
\n\tdestination folder is optional and can be specified as an
\n\targument or as a named parameter.
\n
\n\tThe following options are available:
\n
\n\t-u=<filename>, -u <filename>,
\n\t--url-file=<filename>, --url-file <filename>
\n\t\tSpecify the file containing the Subversion repository list.
\n
\n\t-a=<filename>, -a <filename>,
\n\t--authors-file=[filename], --authors-file [filename]
\n\t\tSpecify the file containing the authors transformation data.
\n
\n\t-d=<folder>, -d <folder>,
\n\t--destination=<folder>, --destination <folder>
\n\t\tThe directory where the new Git repositories should be
\n\t\tsaved. Defaults to the current directory.
\n
\n\t-i=<filename>, -i <filename>,
\n\t--ignore-file=<filename>, --ignore-file <filename>
\n\t\tThe location of a .gitignore file to add to all repositories.
\n
\n\t--quiet
\n\t\tBy default this script is rather verbose since it outputs each revision
\n\t\tnumber as it is processed from Subversion. Since conversion can sometimes
\n\t\ttake hours to complete, this output can be useful. However, this option
\n\t\twill surpress that output.
\n
\n\t--no-metadata
\n\t\tBy default, all converted log messages will include a line starting with
\n\t\t"git-svn-id:" which makes it easy to track down old references to
\n\t\tSubversion revision numbers in existing documentation, bug reports and
\n\t\tarchives. Use this option to get rid of that data. See git svn --help for
\n\t\ta fuller discussion on this option.
\n
\n\t--shared[=(false|true|umask|group|all|world|everybody|0xxx)]
\n\t\tSpecify that the generated git repositories are to be shared amongst
\n\t\tseveral users. See git init --help for more info about this option.
\n
\n\tAny additional options are assumed to be git-svn options and will be passed
\n\talong to that utility directly. Some useful git-svn options are:
\n\t\t--trunk --tags --branches --no-minimize-url
\n\tSee git svn --help for more info about its options.
\n
\nBASIC EXAMPLES
\n\t# Use the long parameter names
\n\t$script --url-file=my-repository-list.txt --authors-file=authors-file.txt --destination=/var/git
\n
\n\t# Use short parameter names
\n\t$script -u my-repository-list.txt -a authors-file.txt /var/git
\n
\nSEE ALSO
\n\tfetch-svn-authors.sh
\n\tsvn-lookup-author.sh
EOF_HELP
);

# Truly quiet git execution. (idea from http://stackoverflow.com/a/8944284)
quiet_git() {
  return `git "$@" </dev/null >>$stdout_file 2>>$stderr_file`;
}

# Output the "Done!" message after a step has completed.
echo_done() {
  msg="${1:-Done.}";
  echo "   $msg" >&2;
  if [[ $printf_cmd == "echo" ]]; then
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
    tmp="destination=$option";
  fi
  parameter=${tmp%%=*}; # Extract option's name.
  value=${tmp##*=};     # Extract option's value.
  # If a value is expected, but not specified inside the parameter, grab the next param.
  if [[ $value == $tmp ]]; then
    if [[ ${2:0:1} == '-' ]]; then
      # The next parameter is a new option, so unset the value.
      value='';
    else
      value=$2;
      shift;
    fi
  fi

  case $parameter in
    u|url-file )      url_file=$value;;
    a|authors-file )  authors_file=$value;;
    d|destination )   destination=$value;;
    i|ignore-file )   ignore_file=$value;;
    q|quiet )         git_cmd="quiet_git"; printf_cmd="printf";;
    shared )          if [[ $value == '' ]]; then
                        gitinit_params="--shared";
                      else
                        gitinit_params="--shared=$value";
                      fi
                      ;;

    h|help )          echo -e $help | less >&2; exit;;

    * ) # Pass any unknown parameters to git-svn directly.
        if [[ $value == '' ]]; then
          gitsvn_params="$gitsvn_params $flag_delimiter$parameter";
        else
          gitsvn_params="$gitsvn_params $flag_delimiter$parameter=$value";
        fi;;
  esac

  # Remove the processed parameter.
  shift;
done

# Check for required parameters.
if [[ $url_file == '' || $authors_file == '' ]]; then
  echo -e $usage >&2;
  exit 1;
fi
# Check for valid files.
if [[ ! -f $url_file ]]; then
  echo "Specified URL file \"$url_file\" does not exist or is not a file." >&2;
  echo -e $usage >&2;
  exit 1;
fi
if [[ ! -f $authors_file ]]; then
  echo "Specified authors file \"$authors_file\" does not exist or is not a file." >&2;
  echo -e $usage >&2;
  exit 1;
fi


# Process each URL in the repository list.
pwd=`pwd`;
tmp_destination="/tmp/tmp-git-repo-$RANDOM";
mkdir -p "$destination";
destination=`cd "$destination"; pwd`; #Absolute path.

# Ensure temporary repository location is empty.
if [[ -e $tmp_destination ]]; then
  echo "Temporary repository location \"$tmp_destination\" already exists. Exiting." >&2;
  exit 1;
fi

cnt_pass=0
cnt_skip=0

while read line
do
  skipping=0

  # Check for 2-field format:  Name [tab] URL
  name=`echo $line | awk '{print $1}'`;
  url=`echo $line | awk '{print $2}'`;

  # Check for simple 1-field format:  URL
  if [[ $url == '' ]]; then
    url=$name;
    name=`basename $url`;
  fi

  # Process each Subversion URL.
  echo >&2;
  echo "At $(date)..." >&2;
  echo "Processing \"$name\" repository at $url..." >&2;

  # Init the final bare repository.
  mkdir "$destination/$name.git";
  cd "$destination/$name.git";
  $git_cmd init --bare $gitinit_params $gitsvn_params;
  $git_cmd symbolic-ref HEAD refs/heads/trunk $gitsvn_params;

  # Clone the original Subversion repository to a temp repository.
  cd "$pwd";
  $printf_cmd " - Cloning repository..." >&2;
  $git_cmd svn clone "$url" -A "$authors_file" --authors-prog="$dir/svn-lookup-author.sh" --stdlayout --quiet "$tmp_destination" $gitsvn_params;
  if [[ $? -eq 0 ]]; then
    echo_done;
  else
    skipping=1;
    echo_done "Failed.";
  fi

  if [[ $skipping -eq 0 ]]; then
    # Create .gitignore file.
    $printf_cmd " - Converting svn:ignore properties into a .gitignore file..." >&2;
    if [[ $ignore_file != '' ]]; then
      cp "$ignore_file" "$tmp_destination/.gitignore";
    fi
    cd "$tmp_destination";
    $git_cmd svn show-ignore --id trunk >> .gitignore;
    $git_cmd add .gitignore;
    $git_cmd commit --author="$git_author" -m 'Convert svn:ignore properties to .gitignore.' $gitsvn_params;
    #git commit --author="git-svn-migrate <nobody@example.org>" -m 'Convert svn:ignore properties to .gitignore.';
    echo_done;

    # Push to final bare repository and remove temp repository.
    $printf_cmd " - Pushing to new bare repository..." >&2;
    $git_cmd remote add bare "$destination/$name.git";
    $git_cmd config remote.bare.push 'refs/remotes/*:refs/heads/*';
    $git_cmd push bare $gitsvn_params;
    # Push the .gitignore commit that resides on master.
    $git_cmd push bare master:trunk $gitsvn_params;
    cd "$pwd";
    rm -r "$tmp_destination";
    echo_done;

    $printf_cmd " - Fix branches..." >&2;
    # Rename Subversion's "trunk" branch to Git's standard "master" branch.
    cd "$destination/$name.git";
    $git_cmd branch -m trunk master;
    # Remove bogus branches of the form "name@REV".
    $git_cmd for-each-ref --format='%(refname)' refs/heads | grep '@[0-9][0-9]*' | cut -d / -f 3- |
    while read ref
    do
      $git_cmd branch -D "$ref";
    done
    echo_done;

    # Convert git-svn tag branches to proper tags.
    $printf_cmd " - Converting svn tag directories to proper git tags..." >&2;
    $git_cmd for-each-ref --format='%(refname)' refs/heads/tags | cut -d / -f 4 |
    while read ref
    do
      $git_cmd tag -a "$ref" -m "Convert \"$ref\" to a proper git tag." "refs/heads/tags/$ref";
      $git_cmd branch -D "tags/$ref";
    done
    echo_done;

    echo "Conversion of \"$name\" completed at $(date)." >&2;
    ((cnt_pass++))
  else
    echo "Conversion of \"$name\" skipped at $(date)." >&2;
    ((cnt_skip++))
  fi
done < "$url_file"

echo >&2;
echo "All done! ($cnt_pass / $(( cnt_pass + cnt_skip ))) passed)" >&2
echo >&2;
if [[ $cnt_skip -ne 0 ]]; then
  echo "($cnt_skip conversions were skipped, check the logs)" >&2
fi
echo >&2;
