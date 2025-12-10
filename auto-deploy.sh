#!/bin/bash

clear
echo "===================================="
echo "     AUTO DEVOPS DEPLOY SYSTEM"
echo "===================================="

# -------------------------------
# 1. INPUTS
# -------------------------------
read -p "Enter project name: " PROJECT_NAME
read -p "Enter project folder path: " PROJECT_PATH
read -p "Enter GitHub username: " GITHUB_USER
read -p "Enter GitHub Personal Access Token: " GITHUB_TOKEN
read -p "Enter Netlify Token: " NETLIFY_AUTH

# -------------------------------
# VALIDATION
# -------------------------------
if [ ! -d "$PROJECT_PATH" ]; then
  echo "❌ ERROR: Project folder not found!"
  exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "❌ ERROR: GitHub token is empty!"
  exit 1
fi

if [ -z "$NETLIFY_AUTH" ]; then
  echo "❌ ERROR: Netlify token is empty!"
  exit 1
fi

echo "✔ Inputs OK"
echo "------------------------------------"

cd "$PROJECT_PATH"

# -------------------------------
# Check if Git repo exists
# -------------------------------
if [ -d ".git" ]; then
    echo "🔄 Existing Git repository detected. Updating..."
    git remote set-url origin "https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$PROJECT_NAME.git" 2>/dev/null
    FIRST_DEPLOY=false
else
    echo "📦 First-time deployment. Initializing Git repo..."
    git init >/dev/null 2>&1
    git remote add origin "https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$PROJECT_NAME.git"
    FIRST_DEPLOY=true
fi

# -------------------------------
# 2. CREATE GITHUB REPO (only first deploy)
# -------------------------------
if [ "$FIRST_DEPLOY" = true ]; then
    echo "📦 Creating GitHub repository: $PROJECT_NAME ..."
    CREATE_REPO=$(curl -s -u "$GITHUB_USER:$GITHUB_TOKEN" \
         https://api.github.com/user/repos \
         -d "{\"name\":\"$PROJECT_NAME\"}")

    if echo "$CREATE_REPO" | grep -q "created_at"; then
        echo "✔ GitHub repo created!"
    else
        echo "❌ GitHub repo creation failed!"
        echo "$CREATE_REPO"
        exit 1
    fi
fi

# -------------------------------
# 3. PUSH PROJECT TO GITHUB
# -------------------------------
echo "⬆ Uploading project to GitHub..."
git add .
git commit -m "auto-deploy update" >/dev/null 2>&1 || echo "⚠ No changes to commit"
git branch -M main 2>/dev/null
git push -u origin main --force >/dev/null
echo "✔ Code uploaded to GitHub!"

# -------------------------------
# 4. CREATE NETLIFY SITE (only first deploy)
# -------------------------------
if [ "$FIRST_DEPLOY" = true ]; then
    RANDOM_ID=$(( RANDOM + 10000 ))
    SITE_NAME="${PROJECT_NAME}-${RANDOM_ID}"
    echo "🌐 Creating Netlify site: $SITE_NAME ..."
    CREATE_NETLIFY=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $NETLIFY_AUTH" \
      -d "{\"name\":\"$SITE_NAME\"}" \
      https://api.netlify.com/api/v1/sites)

    SITE_ID=$(echo "$CREATE_NETLIFY" | grep -o '\"id\":\"[^\"]*' | cut -d '"' -f4)

    if [ -z "$SITE_ID" ]; then
        echo "❌ Netlify site creation failed!"
        echo "$CREATE_NETLIFY"
        exit 1
    fi
    echo "✔ Netlify site created! ID: $SITE_ID"

    # Save info for next updates
    echo "$SITE_NAME" > .netlify_site_name
    echo "$SITE_ID" > .netlify_site_id
else
    SITE_NAME=$(cat .netlify_site_name)
    SITE_ID=$(cat .netlify_site_id)
    echo "🔄 Updating existing Netlify site: $SITE_NAME"
fi

# -------------------------------
# 5. SELECT FOLDER TO DEPLOY
# -------------------------------
read -p "Enter folder to deploy (where index.html is): " PUBLISH_DIR

if [ ! -d "$PROJECT_PATH/$PUBLISH_DIR" ]; then
    echo "❌ ERROR: Folder '$PUBLISH_DIR' does not exist!"
    exit 1
fi

# -------------------------------
# 6. ZIP & DEPLOY TO NETLIFY
# -------------------------------
echo "🚀 Zipping project contents..."
ZIP_FILE="/tmp/${PROJECT_NAME}.zip"
cd "$PROJECT_PATH/$PUBLISH_DIR"
zip -r "$ZIP_FILE" . >/dev/null

if [ ! -f "$ZIP_FILE" ]; then
    echo "❌ Failed to create ZIP file!"
    exit 1
fi
echo "✔ ZIP created: $ZIP_FILE"

echo "🚀 Deploying to Netlify..."
DEPLOY_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/zip" \
  -H "Authorization: Bearer $NETLIFY_AUTH" \
  --data-binary @"$ZIP_FILE" \
  "https://api.netlify.com/api/v1/sites/$SITE_ID/deploys")

if [[ $DEPLOY_RESPONSE == *"state"* ]]; then
    echo "✔ Deployment uploaded!"
    LIVE_URL="https://${SITE_NAME}.netlify.app"
    echo "===================================="
    echo "🎉 DEPLOYMENT COMPLETE"
    echo "🌍 Live URL: $LIVE_URL"
    echo "===================================="
else
    echo "❌ Deployment failed!"
    echo "$DEPLOY_RESPONSE"
fi
