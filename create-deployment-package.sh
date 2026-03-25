#!/bin/bash

# Create a complete deployment package for JIT Access Portal

PACKAGE_NAME="jit-access-portal-package-$(date +%Y%m%d-%H%M%S)"
PACKAGE_DIR="/tmp/${PACKAGE_NAME}"

echo "=================================="
echo "Creating Deployment Package"
echo "=================================="
echo ""

# Create package directory
mkdir -p "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/lambda"
mkdir -p "$PACKAGE_DIR/frontend"
mkdir -p "$PACKAGE_DIR/docs"

echo "📦 Copying Terraform files..."
cp -v main.tf "$PACKAGE_DIR/"
cp -v variables.tf "$PACKAGE_DIR/"
cp -v outputs.tf "$PACKAGE_DIR/"
cp -v terraform.tfvars "$PACKAGE_DIR/"
cp -v approval-workflow.tf "$PACKAGE_DIR/" 2>/dev/null || true
cp -v approval-lambdas.tf "$PACKAGE_DIR/" 2>/dev/null || true
cp -v cognito.tf "$PACKAGE_DIR/" 2>/dev/null || true

echo "📦 Copying Lambda functions..."
cp -v lambda/*.py "$PACKAGE_DIR/lambda/"

echo "📦 Copying frontend files..."
cp -v frontend/index.html "$PACKAGE_DIR/frontend/"

echo "📦 Copying scripts..."
cp -v deploy-frontend.sh "$PACKAGE_DIR/"
cp -v test-portal.sh "$PACKAGE_DIR/"
cp -v get-portal-urls.sh "$PACKAGE_DIR/" 2>/dev/null || true
cp -v import-existing-resources.sh "$PACKAGE_DIR/" 2>/dev/null || true

echo "📦 Copying documentation..."
cp -v README.md "$PACKAGE_DIR/"
cp -v DEPLOY_FROM_SCRATCH.md "$PACKAGE_DIR/docs/"
cp -v TESTING_GUIDE.md "$PACKAGE_DIR/docs/"
cp -v QUICK_TEST_NOW.md "$PACKAGE_DIR/docs/"
cp -v SSO_CONFIGURATION_GUIDE.md "$PACKAGE_DIR/docs/" 2>/dev/null || true
cp -v YOUR_SSO_VALUES.md "$PACKAGE_DIR/docs/" 2>/dev/null || true
cp -v FIXING_STATE_ISSUE.md "$PACKAGE_DIR/docs/" 2>/dev/null || true
cp -v GET_URLS_MANUAL.md "$PACKAGE_DIR/docs/" 2>/dev/null || true

# Create .gitignore
cat > "$PACKAGE_DIR/.gitignore" << 'EOF'
# Terraform
.terraform/
*.tfstate
*.tfstate.*
.terraform.lock.hcl
terraform.tfvars.backup

# Secrets
*.pem
*.key
.env
.env.*

# Lambda packages
*.zip

# Logs
*.log

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo
EOF

# Create quick start script
cat > "$PACKAGE_DIR/quick-start.sh" << 'EOF'
#!/bin/bash

echo "=================================="
echo "JIT Access Portal - Quick Start"
echo "=================================="
echo ""

echo "Step 1: Configure terraform.tfvars"
echo "  Edit terraform.tfvars with your SSO details"
echo ""

echo "Step 2: Deploy infrastructure"
echo "  terraform init"
echo "  terraform validate"
echo "  terraform apply"
echo ""

echo "Step 3: Deploy frontend"
echo "  ./deploy-frontend.sh"
echo ""

echo "Step 4: Create test user"
echo "  aws cognito-idp admin-create-user \\"
echo "    --region us-east-1 \\"
echo "    --user-pool-id \$(terraform output -raw cognito_user_pool_id) \\"
echo "    --username test@example.com \\"
echo "    --user-attributes Name=email,Value=test@example.com"
echo ""

echo "Step 5: Test the portal"
echo "  Visit \$(terraform output -raw website_url)"
echo ""

echo "For detailed instructions, see:"
echo "  - docs/DEPLOY_FROM_SCRATCH.md"
echo "  - docs/TESTING_GUIDE.md"
echo "  - docs/QUICK_TEST_NOW.md"
echo ""
EOF

chmod +x "$PACKAGE_DIR/quick-start.sh"
chmod +x "$PACKAGE_DIR/deploy-frontend.sh"
chmod +x "$PACKAGE_DIR/test-portal.sh"

# Create README for the package
cat > "$PACKAGE_DIR/PACKAGE_README.md" << 'EOF'
# JIT Access Portal - Deployment Package

## What's Included

```
.
├── main.tf                      # Core infrastructure (Lambda, API Gateway, DynamoDB, etc.)
├── approval-workflow.tf         # Step Functions state machine
├── approval-lambdas.tf          # Lambda functions for approval workflow
├── cognito.tf                   # Cognito User Pool configuration
├── variables.tf                 # Input variables
├── outputs.tf                   # Terraform outputs
├── terraform.tfvars             # Your configuration (EDIT THIS!)
├── .gitignore                   # Git ignore rules
├── README.md                    # Project documentation
├── quick-start.sh               # Quick start script
├── lambda/                      # Lambda function source code
│   ├── grant_access.py
│   ├── revoke_access.py
│   ├── request_access.py
│   ├── send_approval_email.py
│   ├── wait_for_approval.py
│   └── process_approval.py
├── frontend/                    # Web portal UI
│   └── index.html
├── deploy-frontend.sh           # Deploy frontend to S3
├── test-portal.sh              # Automated testing script
└── docs/                        # Documentation
    ├── DEPLOY_FROM_SCRATCH.md
    ├── TESTING_GUIDE.md
    ├── QUICK_TEST_NOW.md
    └── SSO_CONFIGURATION_GUIDE.md
```

## Quick Start

### 1. Edit Configuration

```bash
nano terraform.tfvars
```

Update these values:
- `sso_instance_arn` - Your IAM Identity Center instance ARN
- `permission_set_arn` - Your permission set ARN
- `target_account_id` - Your AWS account ID

### 2. Deploy

```bash
# Initialize Terraform
terraform init

# Review what will be created
terraform plan

# Deploy infrastructure
terraform apply

# Deploy frontend
./deploy-frontend.sh
```

### 3. Test

```bash
# Create a test user
aws cognito-idp admin-create-user \
  --region us-east-1 \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username test@example.com \
  --user-attributes Name=email,Value=test@example.com

# Visit the portal
terraform output website_url
```

## Documentation

- **[docs/DEPLOY_FROM_SCRATCH.md](docs/DEPLOY_FROM_SCRATCH.md)** - Complete deployment guide
- **[docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md)** - Testing instructions
- **[docs/QUICK_TEST_NOW.md](docs/QUICK_TEST_NOW.md)** - 5-minute quick test
- **[docs/SSO_CONFIGURATION_GUIDE.md](docs/SSO_CONFIGURATION_GUIDE.md)** - SSO setup details

## Prerequisites

- AWS CLI configured
- Terraform >= 1.5.0
- IAM Identity Center enabled
- SSO Instance ARN and Permission Set ARN

## Support

For issues or questions, check the documentation in the `docs/` folder.
EOF

# Create a file list
echo "📦 Creating file inventory..."
find "$PACKAGE_DIR" -type f > "$PACKAGE_DIR/FILE_LIST.txt"

# Create tarball
echo ""
echo "📦 Creating tarball..."
cd /tmp
tar -czf "${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME"

PACKAGE_SIZE=$(du -h "${PACKAGE_NAME}.tar.gz" | cut -f1)

echo ""
echo "=================================="
echo "Package Created Successfully!"
echo "=================================="
echo ""
echo "📦 Package: /tmp/${PACKAGE_NAME}.tar.gz"
echo "📏 Size: $PACKAGE_SIZE"
echo ""
echo "To extract:"
echo "  tar -xzf ${PACKAGE_NAME}.tar.gz"
echo "  cd ${PACKAGE_NAME}"
echo "  ./quick-start.sh"
echo ""

# Also create a zip file for Windows users
if command -v zip &> /dev/null; then
  echo "📦 Creating zip file for Windows..."
  cd /tmp
  zip -r "${PACKAGE_NAME}.zip" "$PACKAGE_NAME" > /dev/null 2>&1
  ZIP_SIZE=$(du -h "${PACKAGE_NAME}.zip" | cut -f1)
  echo "✅ ZIP created: /tmp/${PACKAGE_NAME}.zip ($ZIP_SIZE)"
fi

echo ""
echo "Files are ready at:"
echo "  - /tmp/${PACKAGE_NAME}.tar.gz (Linux/Mac)"
echo "  - /tmp/${PACKAGE_NAME}.zip (Windows)"
echo ""
