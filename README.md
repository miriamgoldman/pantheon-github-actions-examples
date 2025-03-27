
# Example GitHub Actions

This repository contains various GitHub Action examples, located in the `workflow-files` folder.

To use them in your project:

1. Place both the `.ci` and `.github` folders in the root of your repository.

---

## GitHub Action Setup

To ensure the GitHub Actions run properly, a repository administrator must configure the necessary secrets and environment variables.

### Prerequisites

1. **Install GitHub CLI**  
   ```bash
   brew install gh
   ```

2. **Authenticate to GitHub**  
   ```bash
   gh auth login
   ```

3. **Authenticate to Pantheon using Terminus**  
   ```bash
   terminus auth:login
   ```

4. **Generate a Dedicated SSH Key for Deployments**  
   This guide uses `id_rsa_ghactions` as the SSH key name. You can use a different name, but be consistent throughout.
   ```bash
   USER_EMAIL=$(git config user.email)
   ssh-keygen -t rsa -m PEM -b 4096 -C "$USER_EMAIL" -f id_rsa_ghactions -N ''
   ```
   > ⚠️ **Do not set a passphrase** on the SSH key.

5. **Add the SSH Public Key**  
   - To **Pantheon**: `terminus ssh-key:add id_rsa_ghactions.pub`
   - To **GitHub**:  `gh ssh-key add id_rsa_ghactions.pub`

---

## Setting Repository Secrets

The following secrets must be added using the GitHub CLI as well:
```bash
gh secret set SECRET_NAME < secret_file
```

### TERMINUS SITE

```
echo "MACHINE_NAME_OF_SITE" | gh secret set TERMINUS_SITE
```

## TERMINUS_TOKEN
This will get the Terminus token of the current logged in user (they must have access to the site), and uses the GitHub CLI to save it as a secret.

```
TERMINUS_TOKEN=$(grep -o '"token":"[^"]*' ~/.terminus/cache/tokens/$(terminus whoami) | grep -o '[^"]*$')
echo $TERMINUS_TOKEN | gh secret set TERMINUS_TOKEN
```

## SSH_CONFIG
This reads the ssh_config file contents into a variable, and uses the GitHub CLI to save it as a secret.

```
SSH_CONFIG=$(cat .ci/deploy/pantheon/ssh-config)
echo $SSH_CONFIG | gh secret set SSH_CONFIG
```

## SSH_PRIVATE_KEY
  This reads the ssh key file contents into a variable, and uses the GitHub CLI to save it as a secret. You should delete the public and private key after this, and make sure it does _not_ get committed to your repo. Please ensure the name of the key matches what you configured earlier.
  ```
  SSH_PRIVATE_KEY=$(cat id_rsa_ghactions)
  echo $SSH_PRIVATE_KEY| gh secret set  SSH_PRIVATE_KEY
  ```

  ## KNOWN_HOSTS

  You will likely need to manually go to, in the repo, Settings->Secrets and Variables->Secrets, and create KNOWN_HOSTS as a Secret, with the content being a single space.

  ### GH_TOKEN
  
  For this, you will need to create a personal access token, that is fine-grained. This can be found in the Developer Settings of your profile. This should have no expiration date, and have read and write access to actions, action variables, deployments, discussions, issues, pull requests, secrets, and workflows. 

  Once you have the token, copy the value, and run the following:

  ```
    echo "COPIED TOKEN GOES HERE" | gh secret set GH_TOKEN
  ```

---

## Troubleshooting

If you are getting an accessed denied on any shell scripts run:

`chmod +x path/to/script.sh`

## Notes

- **Security Tip:** Keep your SSH private key secure and never commit it to your repository.
- **Pantheon Access:** Make sure the SSH key is added under your user profile at Pantheon, not just the site dashboard.
- **Custom Workflows:** You can adapt any of the examples in `workflow-files` by editing the `.yml` files under `.github/workflows/`.

---



