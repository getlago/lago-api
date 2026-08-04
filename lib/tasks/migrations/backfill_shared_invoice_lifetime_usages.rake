# frozen_string_literal: true

# Flags `recalculate_invoiced_usage` on lifetime usages whose subscription shares an invoice with
# another subscription, so that `LifetimeUsages::CalculateService` recomputes them with the charge
# fees filtered back to the subscription.
#
# `invoiced_usage_amount_cents` used to sum every charge fee of the invoices covering the
# subscription, including the fees of the siblings billed on the same invoice. The stored value is
# only recomputed when something sets the flag, so an inflated total is served indefinitely until
# the subscription is flagged. Setting the flag makes Clock::RefreshLifetimeUsagesJob pick it up.
#
# The scope is deliberately a superset: it flags every subscription sitting on a shared invoice,
# without checking that the siblings actually carried charge fees. Re-flagging a subscription that
# was already correct is harmless (the recalculation is idempotent), missing one is not.
#
# Terminated subscriptions will not self-heal even with the flag set: CalculateService clears both
# flags without recalculating when the subscription is not active.
#
# Usage:
#   # 1. Preview for a single org (no writes):
#   lago exec api bundle exec rails migrations:backfill_shared_invoice_lifetime_usages \
#     DRY_RUN=true ORGANIZATION_ID=<uuid>
#
#   # 2. Apply for that org:
#   lago exec api bundle exec rails migrations:backfill_shared_invoice_lifetime_usages \
#     DRY_RUN=false ORGANIZATION_ID=<uuid>
#
#   # 3. Apply for everyone (drop ORGANIZATION_ID):
#   lago exec api bundle exec rails migrations:backfill_shared_invoice_lifetime_usages \
#     DRY_RUN=false
#
# Env:
#   DRY_RUN          "false" to apply the flags. Default: true (report only).
#   ORGANIZATION_ID  Restrict to a single organization. Default: all.

namespace :migrations do
  desc "Flag lifetime usages of subscriptions sharing an invoice for recalculation (DRY_RUN=true by default)"
  task backfill_shared_invoice_lifetime_usages: :environment do
    Rails.logger.level = Logger::Severity::ERROR

    batch_size = 1_000
    org_id = ENV["ORGANIZATION_ID"].presence
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    organizations = Organization.with_any_premium_integrations(%w[lifetime_usage progressive_billing])
    organizations = organizations.where(id: org_id) if org_id

    # Same invoices CalculateService sums the charge fees of, restricted to those covering more
    # than one subscription.
    shared_invoices = Invoice.subscription
      .where(organization_id: organizations.select(:id))
      .where(status: %i[finalized draft])
      .where(
        "EXISTS (SELECT 1 FROM invoice_subscriptions this " \
        "JOIN invoice_subscriptions sibling ON sibling.invoice_id = this.invoice_id " \
        "AND sibling.subscription_id != this.subscription_id WHERE this.invoice_id = invoices.id)"
      )

    subscriptions = Subscription.active
      .where(id: InvoiceSubscription.where(invoice_id: shared_invoices.select(:id)).select(:subscription_id))

    scope = LifetimeUsage
      .where(organization_id: organizations.select(:id))
      .where(subscription_id: subscriptions.select(:id))
      .where(recalculate_invoiced_usage: false)

    puts "##################################"
    puts "Shared invoice lifetime usage refresh"
    puts "Organization: #{org_id || "all"}, mode: #{dry_run ? "DRY-RUN (report only)" : "BACKFILL"}"
    puts "=" * 50

    pending = scope.count

    if dry_run
      puts "Lifetime usages that would be flagged for recalculation: #{pending}"
      puts "\nRun again with DRY_RUN=false to apply the flags."
      next
    end

    if pending.zero?
      puts "Nothing to flag ✅"
      next
    end

    puts "Flagging #{pending} lifetime usage(s) in batches of #{batch_size}..."

    flagged = 0
    scope.in_batches(of: batch_size) do |batch|
      flagged += batch.update_all(recalculate_invoiced_usage: true) # rubocop:disable Rails/SkipsModelValidations
      puts "  -> #{flagged}/#{pending} flagged"
    end

    puts "\nDone ✅ Clock::RefreshLifetimeUsagesJob will recompute them on its next run."
  end
end
