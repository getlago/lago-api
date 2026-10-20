# frozen_string_literal: true

# Usage:
#   lago exec api bundle exec rails migrations:backfill_progressive_billing_trigger

namespace :migrations do
  desc "Enqueue the invoices.progressive_billing_trigger backfill on the low_priority queue"
  task backfill_progressive_billing_trigger: :environment do
    Rails.logger.level = Logger::Severity::ERROR

    DatabaseMigrations::BackfillProgressiveBillingTriggerJob.perform_later

    puts "Enqueued DatabaseMigrations::BackfillProgressiveBillingTriggerJob"
    puts "- Make sure a Sidekiq worker is draining the low_priority queue"
    puts "- The job logs \"Finished backfilling invoices.progressive_billing_trigger\" when the walk is over"
  end
end
