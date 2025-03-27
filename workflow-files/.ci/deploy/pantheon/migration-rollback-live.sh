#!/bin/bash
# Rollback migration to prior "old" custom upstream state
# Run with ./migration-rollback-live.sh <site-name>

# Set variables
OLD_UPSTREAM_GIT_URL="git@github.com:org/repo.git"
NEW_UPSTREAM_GIT_URL="git@github.com:org/new-upstream.git"
LIVE_ORG_NEW_UPSTREAM="000000-00000000" # UUID for NEW upstream
LIVE_ORG_OLD_UPSTREAM="000000-00000000" # UUID for OLD upstream

SITE=$1

# Clone the UAT site from Pantheon to local
PANTHEON_GIT_COMMAND=$(terminus connection:info "$SITE.dev" --field=git_command)
PANTHEON_REMOTE=$(terminus connection:info "$SITE.dev" --field=git_url)

set +e
set -x

function setup-workspace {
    
    if [ -d "$GITHUB_WORKSPACE" ]; then
        cd $GITHUB_WORKSPACE
        cd ..
        mkdir migration
        cd migration
        MIGRATION_PATH=$(pwd)
        echo "GITHUB MIGRATION_PATH: $MIGRATION_PATH"
    elif [ ! -d ../../../../migration  ] ; then
        mkdir -p ../../../../migration
        cd ../../../../migration
        MIGRATION_PATH=$(pwd)
        echo "MIGRATION_PATH: $MIGRATION_PATH"
    elif [ -d ../../../../migration  ] ; then
        cd ../../../../migration
        MIGRATION_PATH=$(pwd)
        echo "MIGRATION_PATH: $MIGRATION_PATH"
    fi
    
}


function site-git-clone {
    
    SITE_PATH=$MIGRATION_PATH/$SITE

    echo "SITE_PATH: $SITE_PATH"

    cd $MIGRATION_PATH || exit

    echo "Cloning from Pantheon to migration directory. Value of PANTHEON_REMOTE: $PANTHEON_REMOTE"

    eval "$PANTHEON_GIT_COMMAND"

    cd $SITE_PATH || exit

    git remote add old-upstream $OLD_UPSTREAM_GIT_URL

    git remote add new-upstream $NEW_UPSTREAM_GIT_URL

    echo "Adding Pantheon remote to git repo. Value of PANTHEON_REMOTE: $PANTHEON_REMOTE"

    # Setup pantheon repo remote
    git remote add pantheon $PANTHEON_REMOTE

    git fetch --all

}


function migration-rollback() {

 echo "Rolling back migration for $SITE"

    git checkout master
    # Revert commit history
    git reset --hard pantheon/rollback

     git push pantheon master -f

    git push pantheon master:migration -f

    git push pantheon master -f

    # Set upstream to old upstream
    terminus -n site:upstream:set $SITE $LIVE_ORG_OLD_UPSTREAM --yes

    echo "Migration rollback complete for $SITE"

}

setup-workspace
site-git-clone
migration-rollback
