#!/bin/bash

# Copyright 2010-2011 John Albin Wilkins and contributors.
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
\n\t--authors-file=<filename>, --authors-file <filename>
\n\t\tSpecify the file containing the authors transformation data.
\n
\n\t[-d=]<folder>, [-d ]<folder>,
\n\t[--destination=]<folder>, [--destination ]<folder>
\n\t\tThe directory where the new Git repositories should be
\n\t\tsaved. Defaults to the current directory.
\n\t\tThis parameter can also be passed without the param flag.
\n
\n\t-i=<filename>, -i <filename>,
\n\t--ignore-file=<filename>, --ignore-file <filename>
\n\t\tThe location of a .gitignore file to add to all repositories.
\n
\n\t-f, --force
\n\t\tForce repository creation, even if destination folders exist.
\n\t\tBe sure about this, it can not be undone! You have been warned.
\n
\n\t-q, --quiet
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
\n\tgit-svn-migrate-nohup.sh
\n\tfetch-svn-authors.sh
\n\tsvn-lookup-author.sh
EOF_HELP
);

# Truly quiet git execution. (idea from http://stackoverflow.com/a/8944284)
quiet_git() {
  return $(git "$@" </dev/null >>$stdout_file 2>>$stderr_file);
}

# Output the "Done!" message after a step has completed.
echo_done() {
  msg="${1:-Done.}";
  echo "   $msg" >&2;
  if [[ $_echo == "echo" ]]; then
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
    fi
  fi

  case $parameter in
    u|url-file )      url_file=$value;;
    a|authors-file )  authors_file=$value;;
    d|destination )   destination=$value;;
    i|ignore-file )   ignore_file=$value;;
    f|force )         force=1;;
    q|quiet )         _git="quiet_git"; _echo="echo -n";;
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
tmp_destination="/tmp/tmp-git-repo-$RANDOM";
mkdir -p "$destination";
destination=$(cd "$destination"; pwd); #Absolute path.

# Ensure temporary repository location is empty.
if [[ -e $tmp_destination ]] && [[ $force -eq 0 ]]; then
  echo "Temporary repository location \"$tmp_destination\" already exists. Exiting." >&2;
  exit 1;
fi

# http://stackoverflow.com/a/114861
# http://stackoverflow.com/a/114836
# Ignore empty lines and commented lines (with # or ;)
cnt_total=$(grep -vcE '^$|^[#;]' "$url_file");
cnt_cur=0;
cnt_pass=0;
cnt_skip=0;

while IFS= read -r line
do
  ((cnt_cur++));

  skipping=0;

  # Check for 2-field format:  Name [tab] URL
  name=$(echo $line | awk '{print $1}');
  url=$(echo $line | awk '{print $2}');

  # Check for simple 1-field format:  URL
  if [[ $url == '' ]]; then
    url=$name;
    name=$(basename $url);
  fi

  # The directory where the new git repository is going.
  destination_git="$destination/$name.git";

  # Process each Subversion URL.
  echo >&2;
  echo "( $cnt_cur / $cnt_total ) At $(date)..." >&2;
  echo "Processing \"$name\" repository:" >&2;
  echo " < $url" >&2;
  echo " > $destination_git" >&2;
  echo >&2;

  # Init the final bare repository.
  # Ensure temporary repository location is empty.
  if [[ -e "$destination_git" ]] && [[ $force -eq 0 ]]; then
    echo " - Repository location \"$destination_git\" already exists. Skipping." >&2;
    skipping=1;
  fi

  if [[ $skipping -eq 0 ]]; then
    mkdir -p "$destination_git";
    cd "$destination_git";
    $_git init --bare $gitinit_params $gitsvn_params;
    $_git symbolic-ref HEAD refs/heads/trunk $gitsvn_params;

    # Clone the original Subversion repository to a temp repository.
    cd "$dir";
    $_echo " - Cloning repository..." >&2;
    $_git svn clone "$url" -A "$authors_file" --authors-prog="$dir/svn-lookup-author.sh" --stdlayout --quiet "$tmp_destination" $gitsvn_params;
    if [[ $? -eq 0 ]]; then
      echo_done;
    else
      skipping=1;
      echo_done "Failed.";
    fi
  fi

  if [[ $skipping -eq 0 ]]; then
    # Create .gitignore file.
    $_echo " - svn:ignore => .gitignore file..." >&2;
    if [[ $ignore_file != '' ]]; then
      cp "$ignore_file" "$tmp_destination/.gitignore";
    fi
    cd "$tmp_destination";
    $_git svn show-ignore --id trunk >> .gitignore;
    $_git add .gitignore;
    $_git commit --author="$git_author" -m 'Convert svn:ignore properties to .gitignore.' $gitsvn_params;
    #git commit --author="git-svn-migrate <nobody@example.org>" -m 'Convert svn:ignore properties to .gitignore.';
    echo_done;

    # Push to final bare repository and remove temp repository.
    $_echo " - Pushing to new bare repository..." >&2;
    $_git remote add bare "$destination_git";
    $_git config remote.bare.push 'refs/remotes/*:refs/heads/*';
    $_git push bare $gitsvn_params;
    # Push the .gitignore commit that resides on master.
    $_git push bare master:trunk $gitsvn_params;
    cd "$dir";
    rm -r "$tmp_destination";
    echo_done;

    $_echo " - Fix branches..." >&2;
    # Rename Subversion's "trunk" branch to Git's standard "master" branch.
    cd "$destination_git";
    $_git branch -m trunk master;
    # Remove bogus branches of the form "name@REV".
    $_git for-each-ref --format='%(refname)' refs/heads | grep '@[0-9][0-9]*' | cut -d / -f 3- |
    while read ref
    do
      $_git branch -D "$ref";
    done
    echo_done;

    # Convert git-svn tag branches to proper tags.
    $_echo " - SVN tags => git tags..." >&2;
    $_git for-each-ref --format='%(refname)' refs/heads/tags | cut -d / -f 4 |
    while read ref
    do
      $_git tag -a "$ref" -m "Convert \"$ref\" to a proper git tag." "refs/heads/tags/$ref";
      $_git branch -D "tags/$ref";
    done
    echo_done;
    echo >&2;

    echo "Conversion of \"$name\" completed at $(date)." >&2;
    ((cnt_pass++));
  else
    echo >&2;
    echo "Conversion of \"$name\" skipped at $(date)." >&2;
    ((cnt_skip++));
  fi
done < <(grep -vE '^$|^[#;]' "$url_file")
# http://stackoverflow.com/a/8197412
# http://mywiki.wooledge.org/BashFAQ/024 (ProcessSubstitution)

echo >&2;
echo "All done! ( $cnt_pass / $cnt_total passed )" >&2
echo >&2;
if [[ $cnt_skip -ne 0 ]]; then
  echo "($cnt_skip conversions were skipped, check the output and logs)" >&2
  echo >&2;
fi
