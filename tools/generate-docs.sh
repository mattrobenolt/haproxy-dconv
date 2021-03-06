#!/bin/bash

PROJECT_HOME=$(dirname $(readlink -f $0))
cd $PROJECT_HOME || exit 1

WORK_DIR=$PROJECT_HOME/work

function on_exit()
{
	echo "-- END $(date)"
}

function init()
{
	trap on_exit EXIT

	echo
	echo "-- START $(date)"
	echo "PROJECT_HOME = $PROJECT_HOME"

	echo "Preparing work directories..."
	mkdir -p $WORK_DIR || exit 1
	mkdir -p $WORK_DIR/haproxy || exit 1
	mkdir -p $WORK_DIR/haproxy-dconv || exit 1

	UPDATED=0
	PUSH=0

}

# Needed as "git -C" is only available since git 1.8.5
function git-C()
{
	_gitpath=$1
	shift
	echo "git --git-dir=$_gitpath/.git --work-tree=$_gitpath $@" >&2
	git --git-dir=$_gitpath/.git --work-tree=$_gitpath "$@"
}

function fetch_haproxy_dconv()
{
	echo "Fetching latest haproxy-dconv public version..."
	if [ ! -e $WORK_DIR/haproxy-dconv/master ];
	then
		git clone -v git://github.com/cbonte/haproxy-dconv.git $WORK_DIR/haproxy-dconv/master || exit 1
	fi
	GIT="git-C $WORK_DIR/haproxy-dconv/master"

	OLD_MD5="$($GIT log -1 | md5sum) $($GIT describe --tags)"
	$GIT checkout master && $GIT pull -v
	version=$($GIT describe --tags)
	version=${version%-g*}
	NEW_MD5="$($GIT log -1 | md5sum) $($GIT describe --tags)"
	if [ "$OLD_MD5" != "$NEW_MD5" ];
	then
		UPDATED=1
	fi

	echo "Fetching last haproxy-dconv public pages version..."
	if [ ! -e $WORK_DIR/haproxy-dconv/gh-pages ];
	then
		cp -a $WORK_DIR/haproxy-dconv/master $WORK_DIR/haproxy-dconv/gh-pages || exit 1
	fi
	GIT="git-C $WORK_DIR/haproxy-dconv/gh-pages"

	$GIT checkout gh-pages && $GIT pull -v
}

function fetch_haproxy()
{
	url=$1
	path=$2

	echo "Fetching HAProxy 1.4 repository..."
	if [ ! -e $path ];
	then
		git clone -v $url $path || exit 1
	fi
	GIT="git-C $path"

	$GIT checkout master && $GIT pull -v
}

function _generate_file()
{
	destfile=$1
	git_version=$2
	state=$3

	$GIT checkout $git_version

	git_version_simple=${git_version%-g*}
	doc_version=$(tail -n1 $destfile 2>/dev/null | grep " git:" | sed 's/.* git:\([^ ]*\).*/\1/')
	if [ $UPDATED -eq 1 -o "$git_version" != "$doc_version" ];
	then
		HTAG="VERSION-$(basename $gitpath | sed 's/[.]/\\&/g')"
		if [ "$state" == "snapshot" ];
		then
			base=".."
			HTAG="$HTAG-SNAPSHOT"
		else
			base="."
		fi


		$WORK_DIR/haproxy-dconv/master/haproxy-dconv.py -i $gitpath/doc/configuration.txt -o $destfile --base=$base &&
		echo "<!-- git:$git_version -->" >> $destfile &&
		sed -i "s/\(<\!-- $HTAG -->\)\(.*\)\(<\!-- \/$HTAG -->\)/\1${git_version_simple}\3/" $docroot/index.html

	else
		echo "Already up to date."
	fi

	if [ "$doc_version" != "" -a "$git_version" != "$doc_version" ];
	then
		changelog=$($GIT log --oneline $doc_version..$git_version $gitpath/doc/configuration.txt)
	else
		changelog=""
	fi

	GITDOC="git-C $docroot"
	if [ "$($GITDOC status -s $destfile)" != "" ];
	then
		$GITDOC add $destfile &&
		$GITDOC commit -m "Updating HAProxy $state documentation ${git_version_simple} generated by haproxy-dconv $version" -m "$changelog" $destfile $docroot/index.html &&
		PUSH=1
	fi
}

function generate_docs()
{
	url=$1
	gitpath=$2
	docroot=$3
	filename=$4

	fetch_haproxy $url $gitpath

	GIT="git-C $gitpath"

	$GIT checkout master
	git_version=$($GIT describe --tags --match 'v*')
	git_version_stable=${git_version%-*-g*}

	echo "Generating snapshot version $git_version..."
	_generate_file $docroot/snapshot/$filename $git_version snapshot

	echo "Generating stable version $git_version..."
	_generate_file $docroot/$filename $git_version_stable stable
}

function push()
{
	docroot=$1
	GITDOC="git-C $docroot"

	if [ $PUSH -eq 1 ];
	then
		$GITDOC push origin gh-pages
	fi

}


init
fetch_haproxy_dconv
generate_docs http://git.1wt.eu/git/haproxy-1.4.git/ $WORK_DIR/haproxy/1.4 $WORK_DIR/haproxy-dconv/gh-pages configuration-1.4.html
generate_docs http://git.1wt.eu/git/haproxy-1.5.git/ $WORK_DIR/haproxy/1.5 $WORK_DIR/haproxy-dconv/gh-pages configuration-1.5.html
generate_docs http://git.1wt.eu/git/haproxy.git/ $WORK_DIR/haproxy/1.6 $WORK_DIR/haproxy-dconv/gh-pages configuration-1.6.html
push $WORK_DIR/haproxy-dconv/gh-pages
