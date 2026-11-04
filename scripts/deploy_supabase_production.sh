#!/usr/bin/env bash
# ==============================================================================
# Supabase Production Deployment & Synchronization Script
# Project: Instant Messenger (mpikfmjkblyszjyhyfhz / ap-south-1)
# ==============================================================================

set -euo pipefail

# Expected project configuration
readonly EXPECTED_PROJECT_REF="mpikfmjkblyszjyhyfhz"
readonly EXPECTED_BRANCH="migration/supabase-mvc-foundation"

# Styling
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check flags
DRY_RUN_ONLY=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN_ONLY=true
  log_info "Running in DRY RUN mode. No production changes will be applied."
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $0 [--dry-run]"
  echo "  --dry-run: Perform read-only preflight checks without applying migrations or deploying functions."
  exit 0
fi
# ------------------------------------------------------------------------------
log_info "Step 0: Checking environment prerequisites..."

# Check supabase CLI
if ! command -v supabase &> /dev/null; then
  log_error "Supabase CLI is not installed or not in PATH."
  exit 1
fi

# Check project ref in .temp/project-ref if present
if [[ -f "supabase/.temp/project-ref" ]]; then
  ACTUAL_PROJECT_REF=$(cat supabase/.temp/project-ref | tr -d '[:space:]')
  if [[ "$ACTUAL_PROJECT_REF" != "$EXPECTED_PROJECT_REF" ]]; then
    log_error "Linked project reference mismatch! Expected: $EXPECTED_PROJECT_REF, Found: $ACTUAL_PROJECT_REF"
    exit 1
  fi
  log_success "Project reference verified: $ACTUAL_PROJECT_REF"
else
  log_warn "supabase/.temp/project-ref not found. Will use --project-ref $EXPECTED_PROJECT_REF explicitly."
fi

# Check git branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [[ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]]; then
  log_warn "Current git branch ($CURRENT_BRANCH) differs from expected ($EXPECTED_BRANCH)."
else
  log_success "Git branch verified: $CURRENT_BRANCH"
fi

# ------------------------------------------------------------------------------
# STEP 1: Pre-flight Migration Dry Run
# ------------------------------------------------------------------------------
log_info "Step 1: Running migration pre-flight dry-run..."

DRY_RUN_OUTPUT=$(supabase db push --linked --dry-run --include-all 2>&1)
echo "$DRY_RUN_OUTPUT"

# Verify that only 20261028000002 is staged to push
if echo "$DRY_RUN_OUTPUT" | grep -q "20261028000002_add_forward_and_reply_columns.sql"; then
  log_success "Preflight dry-run confirmed: Pending migration 20261028000002 identified."
elif echo "$DRY_RUN_OUTPUT" | grep -q "Database is up to date"; then
  log_info "Database is already up to date. No pending migrations."
else
  log_error "Unexpected dry-run output. Aborting deployment."
  exit 1
fi

if [[ "$DRY_RUN_ONLY" == true ]]; then
  log_info "Dry run preflight complete. Database and secrets are ready for deployment."
  log_info "To apply changes to production, re-run without --dry-run."
  exit 0
fi

# ------------------------------------------------------------------------------
# STEP 2: Apply Database Migration
# ------------------------------------------------------------------------------
log_info "Step 2: Applying pending database migrations..."

supabase db push --linked --include-all
log_success "Database migrations successfully applied."

# Reload PostgREST schema cache
log_info "Step 2b: Reloading PostgREST schema cache..."
supabase db query --linked "NOTIFY pgrst, 'reload schema';"
log_success "PostgREST schema cache reloaded."

# ------------------------------------------------------------------------------
# STEP 3: Deploy send-push Edge Function
# ------------------------------------------------------------------------------
log_info "Step 3: Deploying updated 'send-push' Edge Function..."

supabase functions deploy send-push --project-ref "$EXPECTED_PROJECT_REF"
log_success "'send-push' Edge Function deployed successfully."

# ------------------------------------------------------------------------------
# STEP 4: Check & Deploy get-zego-token (Optional / Conditional)
# ------------------------------------------------------------------------------
log_info "Step 4: Evaluating 'get-zego-token' Edge Function prerequisites..."

SECRETS_LIST=$(supabase secrets list 2>&1)
if echo "$SECRETS_LIST" | grep -q "ZEGO_APP_ID" && echo "$SECRETS_LIST" | grep -q "ZEGO_SERVER_SECRET"; then
  log_info "ZEGOCLOUD secrets detected. Deploying 'get-zego-token'..."
  supabase functions deploy get-zego-token --project-ref "$EXPECTED_PROJECT_REF"
  log_success "'get-zego-token' Edge Function deployed successfully."
else
  log_warn "ZEGO_APP_ID or ZEGO_SERVER_SECRET is missing from Supabase secrets."
  log_warn "Skipping 'get-zego-token' deployment to avoid 500 runtime errors on calling endpoints."
  log_warn "To deploy get-zego-token later, run:"
  log_warn "  supabase secrets set ZEGO_APP_ID=<id> ZEGO_SERVER_SECRET=<secret>"
  log_warn "  supabase functions deploy get-zego-token --project-ref $EXPECTED_PROJECT_REF"
fi

# ------------------------------------------------------------------------------
# STEP 5: Post-Deployment Verification
# ------------------------------------------------------------------------------
log_info "Step 5: Performing post-deployment production verification..."

# Verify new columns on public.messages
VERIFY_COLUMNS=$(supabase db query --linked "SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name IN ('is_forwarded', 'reply_to_message_id', 'reply_snapshot') ORDER BY column_name;")
echo "$VERIFY_COLUMNS"

# Verify index
VERIFY_INDEX=$(supabase db query --linked "SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'messages' AND indexname = 'idx_messages_reply_to_message_id';")
echo "$VERIFY_INDEX"

# Verify reply validation trigger
VERIFY_TRIGGER=$(supabase db query --linked "SELECT trigger_name, action_statement FROM information_schema.triggers WHERE event_object_schema = 'public' AND event_object_table = 'messages' AND trigger_name = 'trg_validate_message_reply';")
echo "$VERIFY_TRIGGER"

# Verify Edge Functions status
VERIFY_FUNCTIONS=$(supabase functions list)
echo "$VERIFY_FUNCTIONS"

# Final status
log_success "=========================================================="
log_success "Supabase Production Deployment & Synchronization Complete!"
log_success "=========================================================="
