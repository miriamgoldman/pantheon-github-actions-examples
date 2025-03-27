#!/bin/bash
# Setup migration for Acquia -> Pantheon custom upstream migration
# Refactors architecture to use cu-template recs and best practices.  
# Preserves Pantheon site-specific code and config, attempts to resolve merge conficts. 
# Run with ./migration-setup.sh

# Set variables
ACQUIA_AKQA_GIT_URL="git@gitlab.com:akqa-italy-alfaparf/website.git" # gitlab source repo for AKQA Acquia site

OLD_UPSTREAM_GIT_URL="git@github.com:AKQA-group/akqa-italy-alfaparf-website.git"
NEW_UPSTREAM_GIT_URL="git@github.com:org/new-upstream.git"
LIVE_ORG_NEW_UPSTREAM="000000-00000000" # UUID for NEW upstream
LIVE_ORG_OLD_UPSTREAM="000000-00000000" # UUID for OLD upstream
USER_EMAIL=$(git config user.email)
USER_NAME="Github Actions"

SITE=$1

# Clone the site from Pantheon to local
PANTHEON_GIT_COMMAND=$(terminus connection:info "$SITE.dev" --field=git_command)
PANTHEON_REMOTE=$(terminus connection:info "$SITE.dev" --field=git_url)

set +e
set -x

function setup-workspace {
    
    if [ -d "$GITHUB_WORKSPACE" ]; then
        cd $GITHUB_WORKSPACE
        mkdir migration
        cd migration
        MIGRATION_PATH=$(pwd)
        echo "GITHUB MIGRATION_PATH: $MIGRATION_PATH"
    elif [ ! -d ../../../migration  ] ; then
        mkdir -p ../../../migration
        cd ../../../migration
        MIGRATION_PATH=$(pwd)
        echo "MIGRATION_PATH: $MIGRATION_PATH"
    elif [ -d ../../../migration  ] ; then
        cd ../../../migration
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
    git remote add migration-source $ACQUIA_AKQA_GIT_URL

    echo "Adding Pantheon remote to git repo. Value of PANTHEON_REMOTE: $PANTHEON_REMOTE"

    # Setup pantheon repo remote
    git remote add pantheon $PANTHEON_REMOTE

    git fetch migration-source

    git fetch new-upstream

    echo "Creating backup branch for master to allow for easy rollback if needed."

    git checkout -b rollback

    git push pantheon rollback

    git checkout -b migration

    #migration_config_pull

}


# Create a rollback multidev environment on Pantheon from the dev environment
function rollback-multidev-create {
    set +e
    # Push to multidev env, create branch on Pantheon if it doesnt exist
    TERMINUS_ENV_EXISTS=$(terminus env:list "$SITE" --field=ID | grep -w rollback)
    # Doesn't exist; create it
    if [[ -z "$TERMINUS_ENV_EXISTS" ]]
    then
        echo "Site $SITE does not have a rollback multidev. Creating."
        terminus -n multidev:create "$SITE.dev" rollback --yes
    else 
        echo "Site $SITE already has a rollback multidev. Skipping."
    fi
}


# Create a migration multidev environment on Pantheon from the dev environment
function migration-multidev-create {
    set +e
    # Push to multidev env, create branch on Pantheon if it doesnt exist
    TERMINUS_ENV_EXISTS=$(terminus env:list "$SITE" --field=ID | grep -w migration)
    # Doesn't exist; create it
    if [[ -z "$TERMINUS_ENV_EXISTS" ]]
    then
        echo "Site $SITE does not have a migration multidev. Creating."
        terminus -n multidev:create "$SITE.dev" migration --yes
    else 
        echo "Site $SITE already has a migration multidev. Skipping."
    fi
}


function reports-setup {
    if [ ! -d "$MIGRATION_PATH/reports" ]; then
        mkdir $MIGRATION_PATH/reports
    fi

        if [ ! -d "$MIGRATION_PATH/reports/migration-source" ]; then
        cd $MIGRATION_PATH
        cp -r arch/migration/migration-source $MIGRATION_PATH/reports/migration-source
        cd $MIGRATION_PATH
    fi

    if [ ! -d "$MIGRATION_PATH/reports/new-upstream" ]; then
        cd $MIGRATION_PATH
        cp -r arch/migration/new-upstream $MIGRATION_PATH/reports/new-upstream
        cd $MIGRATION_PATH
    fi

    if [ ! -d "$MIGRATION_PATH/reports/$SITE" ]; then
        mkdir $MIGRATION_PATH/reports/$SITE
    fi
    
}

function composer-manifest {

    cd $SITE_PATH || exit
# Allow joachim-n/composer-manifest plugin to avoid interaction prompts
    composer config --no-plugins allow-plugins.joachim-n/composer-manifest true
# Add manifest plugin to track changes to composer packages
    composer require joachim-n/composer-manifest
    cp composer-manifest.yaml ../reports/migration-source/composer-manifest-acsf-source.yaml
    git add . && git commit -m "Add composer manifest and deps to track start state of composer packages."
}

function site-commit-report-pre {

    cd $SITE_PATH || exit

    echo "Generating pre-migration site-specific commit reports for $SITE"

    git log old-upstream/master..pantheon/master --no-merges > ../reports/$SITE/site-specific-commits-pre.txt

}

function site-commit-report-post {

    cd $SITE_PATH || exit

    echo "Generating post-migration site-specific commit reports for $SITE"

    git log new-upstream/master..pantheon/migration --no-merges > $MIGRATION_PATH/reports/$SITE/site-specific-commits-post.txt
}

function merge-config {

    cd $SITE_PATH || exit

    # Use new upstream gitignore as the index for ignored merge conflicts
    cp $MIGRATION_PATH/reports/new-upstream/ignore-index.txt .

    # Implement custom merge strategy via .gitattributes
    echo ignore-index.txt merge=conflicts >> .gitattributes

    # setup git config to usr custom merge strategy
    git config merge.conflicts.driver true

    # Commit merge config files
    git add .gitattributes
    git add ignore-index.txt

    git commit -m "Add gitattributes config to use custom merge strategy."

}

function gitconfig-setup {

    composer config --global github-oauth.github.com $GITHUB_TOKEN

    USER_EMAIL=$(terminus auth:whoami)
    git config --global user.email $USER_EMAIL
    git config --global user.name $USER_NAME

    cat << EOF >> ~/.gitconfig
[alias]
  # Resolve incoming merge conflict in favor of the current working branch
    ours = "!f() { git checkout --ours $@ && git add $@; }; f"
  # Resolve all incoming merge conflicts in favor of the current working branch
    all-ours = "!f() { [ -z \"$@\" ] && set - '.'; git checkout --ours -- \"$@\"; git add -u -- \"$@\"; }; f"
  # Resolve incoming merge conflict in favor of the upstream repo
    theirs = "!f() { git checkout --theirs $@ && git add $@; }; f"
  # Resolve all incoming merge conflicts in favor of the upstream repo
    all-theirs = "!f() { [ -z \"$@\" ] && set - '.'; git checkout --theirs -- \"$@\"; git add -u -- \"$@\"; }; f"
  # List merge conflicts
    conflicts = !git ls-files -u | cut -f 2 | sort -u
EOF

    echo "Content of ~/.gitconfig:" && cat ~/.gitconfig
}

function merge-hist {

    cd $SITE_PATH || exit

    git checkout migration

    echo "Cleaning up vendored files."

    git rm -r --cached web/modules/contrib
    git rm -r --cached web/themes/contrib
    git rm -r --cached web/core
    git rm -r --cached vendor
    git rm -r --cached tests/vendor
    git rm --cached web/web.config
    git rm --cached web/robots.txt
    git rm --cached web/.ht.router.php
    git commit -m "Remove vendored files."
    remove_untracked
    git_cleanup

    git pull new-upstream master -X theirs  --ff --no-edit
    
    resolve-conflicts

    git status

     # commit resulting changed files
     git add . && git commit -m "Migrated to updated upstream."

}

function resolve-conflicts {

    cd $SITE_PATH || exit

    # SET CONFLICTS_LIST to the output of git conflicts
  CONFLICTS_LIST=$(git conflicts)

    if [[ -n "$CONFLICTS_LIST" ]]; then
      echo "Merge conflicts found, attempting to resolve."
     
      git all-theirs
      git status
      remove_untracked
      
      git commit -m "Resolving merge conflicts."
    else 
      echo "No merge conflicts found."
    fi
}


function remove_untracked {

    cd $SITE_PATH || exit

    UNTRACKED_FILES=$(git status -u)

    if [[ -n "$UNTRACKED_FILES" ]]; then
      echo "Untracked files found, attempting to remove."
      git clean -f -d
    else
      echo "No untracked files found."
    fi
}

function git_cleanup {

    cd $SITE_PATH || exit 

    MODIFIED_OR_ADDED_LIST=$(git status --porcelain)

  if [[ -n "$MODIFIED_OR_ADDED_LIST" ]]; then
    echo "Uncommitted files found:"
    echo $MODIFIED_OR_ADDED_LIST

    echo  "Attempting to remove uncommitted files."
    git clean -fdX
    git stash
  fi

}



# Generate list of composer packages which exist in the Pantheon site repo, but not in the GitHub custom upstream. 
# These must be re-added to the site's composer.json during the migration.

    function composer-add-custom {

        cd $SITE_PATH || exit
        

        # If upstream composer-manifest.yaml doesnt exist, generate it and then remove it

        if [[ ! -f $MIGRATION_PATH/reports/new-upstream/composer-manifest-new-upstream.yaml  ]]; then
            # Allow joachim-n/composer-manifest plugin to avoid interaction prompts
            composer config --no-plugins allow-plugins.joachim-n/composer-manifest true
            # Add manifest plugin to track changes to composer packages
            composer require joachim-n/composer-manifest
            cp composer-manifest.yaml ../reports/$SITE/composer-manifest-new-upstream.yaml
        fi

        composer config --no-plugins allow-plugins.joachim-n/composer-manifest false
        composer remove joachim-n/composer-manifest --no-update
        rm composer-manifest.yaml

        diff -c $MIGRATION_PATH/reports/$SITE/composer-manifest-old-upstream.yaml $MIGRATION_PATH/reports/new-upstream/composer-manifest-new-upstream.yaml | grep "^-[^-]" > composer-diff.txt

        sed 's/^-     //' composer-diff.txt > composer-packages.txt

        sed 's/^-     //' composer-diff.txt > $MIGRATION_PATH/reports/$SITE/composer-packages.txt

        while read line; do
            package=$(echo $line | cut -d ':' -f 1)
            version=$(echo $line | cut -d ':' -f 2 | tr -d '[:space:]')
            composer require $package:$version --no-update
        done < composer-packages.txt

        git add composer.json

        rm composer-diff.txt
        rm composer-packages.txt

        git commit -m "Add site-specific composer packages to composer.json."

        check-composer

    }

function check-composer {

    cd $SITE_PATH || exit

    echo "Running composer checks on $SITE."

    rm -rf vendor web/core web/modules/contrib web/profiles/contrib web/themes/contrib

  composer validate --no-check-all --ansi && true
  CHECK_BUILD="$?"

  if [[ "$CHECK_BUILD" == 2 ]]; then
    echo "Composer checks failed, attempt to auto-resolve errors on Pantheon remote."

    rm composer.lock

    # Rebuild lockfile and test IC build
    rm -rf vendor web/core web/modules/contrib web/profiles/contrib web/themes/contrib
    composer clearcache --ansi
    composer install --ansi --no-interaction --optimize-autoloader

    git add composer.lock

    git commit -m "Resolve dependency conflicts on Pantheon site repo."
  else
    echo "Composer checks passed."
  fi

}

function platform-arch-review {

     # Create platform architecture review in ../reports/$SITE/platform-arch-review.txt
    terminus drush $SITE.dev -- status > $MIGRATION_PATH/reports/$SITE/platform-arch-review.txt

    # Pending updates
    terminus drush $SITE.dev -- updbst >> $MIGRATION_PATH/reports/$SITE/platform-arch-review.txt 

    # Config status
    terminus drush $SITE.dev -- config:status >> $MIGRATION_PATH/reports/$SITE/platform-arch-review.txt 

    # check if there are any overridden config files by grepping for Different or "database", run drupal-config-export if so
    #check_config=$(terminus drush $SITE.migration -- config:status | grep -E 'Different'\|'database')

    if [[ -n "$check_config" ]]; then
        echo "Config files are different, exporting config to vcs."
     # drupal-config-export
    else 
        echo "Config synced, not exporting config."
    fi

    # Drupal module report
    terminus drush $SITE.dev -- pm:list >> $MIGRATION_PATH/reports/$SITE/platform-arch-review.txt

for site in $(./vendor/bin/drush sa --format=list | grep 01live  | grep acsf-drush-alfaparf); do
  echo "Status report for $site" > $MIGRATION_PATH/reports/migration-source/source-status.txt
  drush $site -- acsf-info >> $MIGRATION_PATH/reports/migration-source/source-status.txt
  drush $site -- st >> $MIGRATION_PATH/reports/migration-source/source-status.txt
  drush $site -- updbst >> $MIGRATION_PATH/reports/migration-source/source-status.txt
  drush $site -- cst >> $MIGRATION_PATH/reports/migration-source/source-status.txt
  drush $site config:status --filter="name*=config_split.config_split" --field=name | xargs -I {} drush $site -- config:get {} status --include-overridden 2>&1 >> $MIGRATION_PATH/reports/migration-source/source-status.txt
done
}



function drupal-arch-report {

    # Create drupal architecture report in ../reports/$SITE/drupal-arch-report.txt
    terminus drush $SITE.dev -- status > $MIGRATION_PATH/reports/$SITE/drupal-arch-report.txt

    # Pending updates
    terminus drush $SITE.dev -- updbst >> $MIGRATION_PATH/reports/$SITE/drupal-arch-report.txt 

    # Config status
    terminus drush $SITE.dev -- config:status >> $MIGRATION_PATH/reports/$SITE/drupal-arch-report.txt 

    # check if there are any overridden config files by grepping for Different or "database", run drupal-config-export if so
    check_config=$(terminus drush $SITE.migration -- config:status | grep -E 'Different'\|'database')

    if [[ -n "$check_config" ]]; then
        echo "Config files are different, exporting config to vcs."
      drupal-config-export
    else 
        echo "Config synced, not exporting config."
    fi

    # Drupal module report
    terminus drush $SITE.dev -- pm:list >> $MIGRATION_PATH/reports/$SITE/drupal-arch-report.txt

}

# Export site-specific Drupal configuration from each site on Pantheon, if any exists

function drupal-config-export {

    # Set connection mode to sftp
    terminus connection:set $SITE.migration sftp

    #  Export config on $SITE.migration with drush config:export
    terminus drush $SITE.migration -- config:export --yes

    # Commit config to git repo
    terminus env:commit $SITE.migration --message="Export site-specific config." --force

    # Set connection mode to git
    terminus connection:set $SITE.migration git --yes

    # Pull config to local repo
    git pull pantheon migration -X theirs --ff --no-edit
    
}

function migration_config_pull {

    cd $SITE_PATH || exit

    echo "Pulling updated config in $SITE live Pantheon not yet exported to vcs."

    # Set connection mode to sftp
    #terminus connection:set $SITE.migration sftp
     drush config:pull @$SITE.live @self



    #  Export config on $SITE.migration with drush config:export
    #terminus drush $SITE.migration -- config:export --yes

    # Commit config to git repo
    #terminus env:commit $SITE.migration --message="Export site-specific config." --force

    # Set connection mode to git
    #terminus connection:set $SITE.migration git --yes

    # Pull config to local repo
   # git pull pantheon migration -X theirs --ff --no-edit
    
}

function push-new {
    # Force push the migrated upstrean code to the Pantheon master branch
    echo "Pushing migrated upstream to Pantheon master branch."

    git push pantheon migration -f
    
    
    git push pantheon migration:master -f

    # sync migration to canary multidev if it exists
    TERMINUS_ENV_EXISTS=$(terminus env:list "$SITE" --field=ID | grep -w canary)
    # Doesn't exist; create it
    if [[ -z "$TERMINUS_ENV_EXISTS" ]]
    then
        echo "Site $SITE has a canary multidev. Syncing code."
        git push pantheon migration:canary -f
    else 
        echo "Site $SITE does not have a canary multidev. Skipping code sync."
    fi



}

function switch-upstream {

    # Switch each site to the new custom upstream
    terminus -n site:upstream:set $SITE $LIVE_ORG_NEW_UPSTREAM --yes


}

setup-workspace
reports-setup
gitconfig-setup
site-git-clone
platform-arch-report
migration-multidev-create
rollback-multidev-create
composer-manifest
site-commit-report-pre
merge-config
drupal-arch-report
merge-hist
composer-add-custom
push-new
switch-upstream