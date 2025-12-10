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

# -------------------------------
# SAFE & UNIQUE repo name
# -------------------------------
TIMESTAMP=$(date +%s)
SAFE_PROJECT_NAME="${PROJECT_NAME}-${TIMESTAMP}"

echo "🔧 Generated safe GitHub repo name: $SAFE_PROJECT_NAME"

# -------------------------------
# 2. CHECK IF REPO ALREADY EXISTS
# -------------------------------
CHECK_REPO=$(curl -s -u "$GITHUB_USER:$GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_USER/$PROJECT_NAME")

if echo "$CHECK_REPO" | grep -q "\"full_name\""; then
    echo "⚠ Repo '$PROJECT_NAME' already exists!"
    echo "Using unique repo name: $SAFE_PROJECT_NAME"
    FINAL_REPO_NAME="$SAFE_PROJECT_NAME"
else
    FINAL_REPO_NAME="$PROJECT_NAME"
fi

# -------------------------------
# 3. CREATE GITHUB REPO
# -------------------------------
echo "📦 Creating GitHub repository: $FINAL_REPO_NAME ..."
CREATE_REPO=$(curl -s -u "$GITHUB_USER:$GITHUB_TOKEN" \
     https://api.github.com/user/repos \
     -d "{\"name\":\"$FINAL_REPO_NAME\"}")

if echo "$CREATE_REPO" | grep -q "created_at"; then
    echo "✔ GitHub repo created!"
else
    echo "❌ GitHub repo creation failed!"
    echo "$CREATE_REPO"
    exit 1
fi

# -------------------------------
# 4. PUSH PROJECT TO GITHUB
# -------------------------------
echo "⬆ Uploading project to GitHub..."

cd "$PROJECT_PATH"

git init >/dev/null 2>&1
git remote remove origin 2>/dev/null
git remote add origin "https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$FINAL_REPO_NAME.git"
git add .
git commit -m "auto-deploy" >/dev/null
git branch -M main
git push -u origin main --force >/dev/null

echo "✔ Code uploaded to GitHub!"

# -------------------------------
# 5. CREATE NETLIFY SITE
# -------------------------------
RANDOM_ID=$(( RANDOM + 10000 ))
SITE_NAME="${FINAL_REPO_NAME}-${RANDOM_ID}"

echo "🌐 Creating Netlify site: $SITE_NAME ..."
CREATE_NETLIFY=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $NETLIFY_AUTH" \
  -d "{\"name\":\"$SITE_NAME\"}" \
  https://api.netlify.com/api/v1/sites)

SITE_ID=$(echo "$CREATE_NETLIFY" | grep -o '"id":"[^"]*' | cut -d '"' -f4)

if [ -z "$SITE_ID" ]; then
    echo "❌ Netlify site creation failed!"
    echo "$CREATE_NETLIFY"
    exit 1
fi

echo "✔ Netlify site created! ID: $SITE_ID"

# -------------------------------
# 5. SELECT FOLDER TO DEPLOY
# -------------------------------
echo "📁 Select the folder to deploy (where index.html is)."
echo "Example: . (current folder), build, dist, public"
read -p "Enter folder name: " PUBLISH_DIR

# Remove leading/trailing slashes
PUBLISH_DIR="${PUBLISH_DIR%/}"

# Make full path
FULL_PATH="$PROJECT_PATH/$PUBLISH_DIR"

if [ ! -d "$FULL_PATH" ]; then
    echo "❌ ERROR: Folder '$FULL_PATH' does not exist!"
    exit 1
fi

# Check if index.html exists
if [ ! -f "$FULL_PATH/index.html" ]; then
    echo "❌ ERROR: index.html not found in '$FULL_PATH'!"
    exit 1
fi


# -------------------------------
# 7. ZIP & DEPLOY TO NETLIFY
# -------------------------------
echo "🚀 Zipping project contents..."
ZIP_FILE="/tmp/${FINAL_REPO_NAME}.zip"
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
    echo "✔ Deployment successful!"
    LIVE_URL="https://${SITE_NAME}.netlify.app"
    echo "===================================="
    echo "🎉 DEPLOYMENT COMPLETE"
    echo "🌍 Live URL: $LIVE_URL"
    echo "===================================="
else
    echo "❌ Deployment failed!"
    echo "$DEPLOY_RESPONSE"
fi
