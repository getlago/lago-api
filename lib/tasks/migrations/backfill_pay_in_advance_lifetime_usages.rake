# frozen_string_literal: true

# Flags `recalculate_invoiced_usage` on lifetime usages whose subscription has at least one
# immediate pay-in-advance charge invoice, so that `LifetimeUsages::CalculateService` recomputes
# them with the de-duplicated current usage.
#
# Subscriptions with ongoing activity self-heal on the next recalculation, but a dormant one keeps
# serving the doubled total forever, because the current usage is only refreshed when something
# happens on the subscription. Setting the flag makes Clock::RefreshLifetimeUsagesJob pick them up.
#
# Terminated subscriptions will not self-heal even with the flag set: CalculateService clears both
# flags without recalculating when the subscription is not active.
#
# Usage:
#   # 1. Preview for a single org (no writes):
#   lago exec api bundle exec rails migrations:backfill_pay_in_advance_lifetime_usages \
#     DRY_RUN=true ORGANIZATION_ID=<uuid>
#
#   # 2. Apply for that org:
#   lago exec api bundle exec rails migrations:backfill_pay_in_advance_lifetime_usages \
#     DRY_RUN=false ORGANIZATION_ID=<uuid>
#
#   # 3. Apply for everyone (drop ORGANIZATION_ID):
#   lago exec api bundle exec rails migrations:backfill_pay_in_advance_lifetime_usages \
#     DRY_RUN=false
#
# Env:
#   DRY_RUN          "false" to apply the flags. Default: true (report only).
#   ORGANIZATION_ID  Restrict to a single organization. Default: all.

namespace :migrations do
  desc "Flag lifetime usages with immediate pay-in-advance invoices for recalculation (DRY_RUN=true by default)"
  task backfill_pay_in_advance_lifetime_usages: :environment do
    Rails.logger.level = Logger::Severity::ERROR

    batch_size = 1_000
    org_id = ENV["ORGANIZATION_ID"].presence
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    organizations = Organization.with_any_premium_integrations(%w[lifetime_usage progressive_billing])
    organizations = organizations.where(id: org_id) if org_id

    subscriptions = Subscription.active
      .where(id: InvoiceSubscription.in_advance_charge.select(:subscription_id))

    scope = LifetimeUsage
      .where(organization_id: organizations.select(:id))
      .where(subscription_id: subscriptions.select(:id))
      .where(recalculate_invoiced_usage: false)

    puts "##################################"
    puts "Pay-in-advance lifetime usage refresh"
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
