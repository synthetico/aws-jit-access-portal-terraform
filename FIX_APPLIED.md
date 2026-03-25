# Fix Applied: Terraform Template Syntax Issue

## Problem

When running `terraform apply`, you got an error related to single quotes in `index.html`. This was because:

1. Terraform was using `templatefile()` to process the HTML file
2. The HTML contains JavaScript with template literals using `${...}` syntax
3. Terraform's template function also uses `${...}` for interpolation
4. This caused a syntax conflict

## Solution Applied

Changed the S3 object resource from using `templatefile()` to using `source`:

**Before:**
```hcl
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  content_type = "text/html"
  content = templatefile("${path.module}/frontend/index.html", {
    api_endpoint = "${aws_apigatewayv2_stage.main.invoke_url}/request-access"
  })
  etag = filemd5("${path.module}/frontend/index.html")
}
```

**After:**
```hcl
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  content_type = "text/html"
  source       = "${path.module}/frontend/index.html"
  etag = filemd5("${path.module}/frontend/index.html")
}
```

## What Changed

- Removed `templatefile()` function
- Removed template variables (we weren't using them anyway)
- Changed `content =` to `source =` which reads the file directly without processing
- The HTML file is now uploaded to S3 exactly as-is

## Verification

```bash
terraform validate
```

Output: **Success! The configuration is valid.**

## Now You Can Deploy

```bash
terraform apply
```

This should work without any template syntax errors.

## Why This Fix Works

Using `source` instead of `content` with `templatefile()`:
- Uploads the file as-is without template processing
- Avoids conflicts with JavaScript template literals
- Simpler and more appropriate for static HTML files
- The HTML already has the API URL hardcoded, so no templating needed

## Alternative Solution (Not Used)

If we needed to use `templatefile()` for variable substitution, we could escape the JavaScript template literals:

```javascript
// Instead of:
className = `status ${type}`;

// Use:
className = `status $${type}`;  // Double $ escapes it for Terraform
```

But since we're not actually using any Terraform variables in the HTML, using `source` is cleaner.
