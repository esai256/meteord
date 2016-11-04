#!/bin/sh

set -e # Exit on any bad exit status
my_dir=`dirname $0`

# Shouldn't matter, but just in case.
export METEOR_NO_RELEASE_CHECK=1

# Because of CDN issues.
: ${METEOR_WAREHOUSE_URLBASE:="https://d3fm2vapipm3k9.cloudfront.net"}
export METEOR_WAREHOUSE_URLBASE

copied_app_path=$HOME/copied-app
build_dir=$HOME/.build

# sometimes, directly copied folder cause some weird issues
# this fixes that
echo "=> Copying the app"
cp -R $HOME/app $copied_app_path
cd $copied_app_path

# Function which makes a Meteor version number comparable.
cver () {
  echo $1 | perl -n \
  -e '@ver = /^(?:[^\@]+\@)?([0-9]+)\.([0-9]+)(?:\.([0-9]+))?(?:\.([0-9]+))?/;' \
  -e 'printf "%04s%04s%04s%04s", @ver;'
}

if ! [ -d ".meteor" ]; then
  echo "********************************************************"
  echo "*** There is no '.meteor' directory in this project! ***"
  echo "********************************************************"
  exit 1
fi

if ! [ -f ".meteor/release" ]; then
  echo "*************************************************"
  echo "There is no .meteor/release file on this project."
  echo "Make sure the project is configured properly."
  echo "*************************************************"
  exit 1
fi

# First, try to get the Meteor version from the .meteor/release file in the app.
if [ -z "$METEOR_RELEASE" ]; then
  METEOR_RELEASE="$(grep "^METEOR@" .meteor/release | sed 's/^METEOR@//;')"
fi

# Check to make sure it's not a generally unpublished version, like beta or RC.
# These aren't generally available as direct bootstrap downloads.
if ! [ -z "$METEOR_RELEASE" ]; then
  if (echo "$METEOR_RELEASE" | grep -Eq '\-(alpha|beta|rc)'); then
    echo "=> [warn] Beta and RC releases cannot use the streamlined downloading..."
    unset METEOR_RELEASE
  fi
fi

# Would like to use a cached Meteor here at some point, but for now,
# download the installer, attempting to use the preferred version, from
# the install.meteor.com script
if true; then
  curl -sL "https://install.meteor.com/?release=${METEOR_RELEASE}" \
    > /tmp/install_meteor.sh

  if [ -z "${METEOR_RELEASE}" ]; then
    # Read it from the install file.
    echo "Setting METEOR_RELEASE from the installer"
    eval "METEOR_RELEASE=$( \
      cat /tmp/install_meteor.sh | \
      grep '^RELEASE="[0-9\.a-z-]\+"$' | \
      sed 's/RELEASE=//;s/"//g' \
    )"
  fi

  echo "=> Running the ${METEOR_RELEASE} installer..."
  cat /tmp/install_meteor.sh | sed s/--progress-bar/-sL/g | /bin/sh
fi

# Useful for various hot-patches/optimizations
meteor_bin="$HOME/.meteor/meteor"
meteor_bin_symlink="$(readlink $meteor_bin)"
meteor_tool_dir="$(dirname "${meteor_bin_symlink}")"

## For future use:
## ....to symlink a cached Meteor's `meteor` execuatable
#LAUNCHER="$HOME/.meteor/${meteor_tool_dir}/scripts/admin/launch-meteor"
#echo "Making 'meteor' Symlink from ${LAUNCHER}"
#ln $LAUNCHER -sf /usr/local/bin/meteor

unsafe_perm_flag=""
if [ "$EUID" -eq 0 ] && $(cver "${METEOR_RELEASE}") -eq $(cver "1.4.2") ]; then
  # If the primary release requires the --unsafe-perm flag, let's pass it.
  unsafe_perm_flag="--unsafe-perm"

  echo "=> Hot-Patching 1.4.2 release to not pass --unsafe-perm to springboarded version..."
  perl -0pi.bak \
    -e 's/(^\h+var newArgv.*?$)/$1\n\n  newArgv = _.filter(newArgv, function (arg) { return arg !== "--unsafe-perm"; });/ms' \
    $HOME/.meteor/${meteor_tool_dir}/tools/cli/main.js
  echo "...done"
fi

echo "=> App Meteor Version"
meteor_version_app=$(cat .meteor/release)
echo "  > ${meteor_version_app}"

echo "=> Executing NPM install --production"
$meteor_bin npm install --production 2>&1 > /dev/null

echo "=> Executing Meteor Build..."

$meteor_bin build \
  ${unsafe_perm_flag} \
  --directory $build_dir

echo "=> Executing NPM install within Bundle"
(cd ${build_dir}/bundle/programs/server/ && npm install --unsafe-perm)

echo "=> Moving bundle"
mv ${build_dir}/bundle $HOME/built_app

echo "=> Cleaning up"
# cleanup
echo " => copied_app_path"
rm -rf $copied_app_path
echo " => build_dir"
rm -rf ${build_dir}
echo " => .meteor"
rm -rf ~/.meteor

set +e