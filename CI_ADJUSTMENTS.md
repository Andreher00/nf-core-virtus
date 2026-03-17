# GitHub Actions CI Adjustments for Fork

This document describes the adjustments needed for GitHub Actions workflows to run properly in a forked repository.

## Required Changes

### 1. Linting Workflow - Python Version Downgrade

**File:** `.github/workflows/linting.yml`

**Issue:** Python 3.14 is not yet available in GitHub Actions runners.

**Fix:** Change Python version from 3.14 to 3.12

```yaml
# Before
- uses: actions/setup-python@e797f83bcb11b83ae66e0230d6156d7c80228e7c # v6
  with:
    python-version: "3.14"
    architecture: "x64"

# After
- uses: actions/setup-python@e797f83bcb11b83ae66e0230d6156d7c80228e7c # v6
  with:
    python-version: "3.12"
    architecture: "x64"
```

### 2. nf-test Workflow - Disable for Forks

**File:** `.github/workflows/nf-test.yml`

**Issue:** This workflow requires self-hosted runners that are not available in forks.

**Fix:** Comment out the pull request trigger

```yaml
# Before
on:
  pull_request:
    paths-ignore:
      - "docs/**"
      - "**/meta.yml"
      - "**/*.md"
      - "**/*.png"
      - "**/*.svg"
  release:
    types: [published]
  workflow_dispatch:

# After
on:
  # Disabled for fork - requires self-hosted runners
  # pull_request:
  #   paths-ignore:
  #     - "docs/**"
  #     - "**/meta.yml"
  #     - "**/*.md"
  #     - "**/*.png"
  #     - "**/*.svg"
  release:
    types: [published]
  workflow_dispatch:
```

### 3. AWS Test Workflow - Disable for Forks

**File:** `.github/workflows/awstest.yml`

**Issue:** This workflow requires AWS credentials and infrastructure not available in forks.

**Fix:** Comment out the workflow_dispatch trigger

```yaml
# Before
on:
  workflow_dispatch:

# After
on:
  # Disabled for fork - requires AWS credentials
  # workflow_dispatch:
```

## Applying These Changes

**Note:** These files cannot be modified programmatically because they require the `workflow` scope on the GitHub token. You must make these changes manually:

1. Create a new branch:
   ```bash
   git checkout -b fix-ci-workflows
   ```

2. Edit the three files mentioned above

3. Commit and push:
   ```bash
   git add .github/workflows/linting.yml .github/workflows/nf-test.yml .github/workflows/awstest.yml
   git commit -m "ci: adjust workflows for fork compatibility"
   git push -u origin fix-ci-workflows
   ```

## Why These Changes Are Needed

- **Python 3.14**: Not yet released as stable, so GitHub Actions runners don't have it
- **nf-test**: Requires self-hosted runners configured with specific infrastructure
- **AWS tests**: Requires AWS account credentials and configured AWS infrastructure

These changes ensure that only workflows compatible with standard GitHub Actions runners will execute in the fork.

## Testing

After making these changes:

1. The linting workflow should run successfully on pull requests
2. The CI workflow (tests) should run successfully
3. The nf-test and AWS workflows will only run when manually triggered or on releases

You can verify the changes by creating a test PR and checking the Actions tab.
