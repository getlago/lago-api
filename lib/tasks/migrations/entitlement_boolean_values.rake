# frozen_string_literal: true

# Usage:
#   # Backfill everything:
#   lago exec api bundle exec rails migrations:backfill_entitlement_boolean_values
#
#   # Resume a chain that died, from the last id it reported:
#   lago exec api bundle exec rails migrations:backfill_entitlement_boolean_values START_AFTER=<entitlement value id>

namespace :migrations do
  desc "Enqueue the rewrite of boolean entitlement values stored as t or f on the low_priority queue"
  task backfill_entitlement_boolean_values: :environment do
    Rails.logger.level = Logger::Severity::ERROR

    start_after = ENV["START_AFTER"].presence

    if start_after && !Entitlement::EntitlementValue.unscoped.exists?(id: start_after)
      abort "Unknown START_AFTER entitlement value id #{start_after}"
    end

    puts "##################################"
    puts "Boolean entitlement values backfill"
    puts "Starting #{start_after ? "after entitlement value #{start_after}" : "from the beginning"}"
    puts "=" * 50

    # The uniqueness lock refuses a batch already enqueued or running: perform_later then returns false.
    unless DatabaseMigrations::BackfillEntitlementBooleanValuesJob.perform_later(start_after)
      abort "Not enqueued: a backfill job is already enqueued or running for this START_AFTER"
    end

    puts "Enqueued DatabaseMigrations::BackfillEntitlementBooleanValuesJob"
    puts "- Make sure a Sidekiq worker is draining the low_priority queue"
    puts "- The job logs \"Finished backfilling boolean entitlement values\" when the walk is over,"
    puts "  and reports to Sentry if any value is still stored as t or f"
  end
end
