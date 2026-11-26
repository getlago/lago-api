# frozen_string_literal: true

# One-off: a subscription's daily usage was diffed against the earlier rows of its period that end at the same time.
# A period's end can move while its rows are written: a termination ends the last period at the termination, so the
# row written from the terminating invoice found no earlier row, and its usage_diff repeated the usage of the rows
# before it. Rows are now chained on the period start only.
#
# It recomputes the usage_diff of the rows whose previous row in the period ends at another time: the rows whose diff
# that change affects. A row whose diff is already right is left as it is, so a run that stops can be run again and a
# second run changes nothing. Dry run by default: nothing is written.
class RechainDailyUsageDiffs
  Error = Class.new(StandardError)

  def self.call(**, &) = new(**).call(&)

  def initialize(organization_id: nil, dry_run: true)
    @organization_id = organization_id
    @dry_run = dry_run
  end

  # Yields one entry per row whose diff changes
  def call
    daily_usages.find_each do |daily_usage|
      usage_diff = DailyUsages::ComputeDiffService.call!(daily_usage:).usage_diff
      next if usage_diff == daily_usage.usage_diff

      entry = {
        daily_usage_id: daily_usage.id,
        organization_id: daily_usage.organization_id,
        subscription_id: daily_usage.subscription_id,
        usage_date: daily_usage.usage_date,
        status: dry_run ? :would_recompute : :recomputed,
        amount_cents_before: amount_cents(daily_usage.usage_diff),
        amount_cents_after: amount_cents(usage_diff)
      }

      daily_usage.update!(usage_diff:) unless dry_run
      yield entry
    rescue => e
      raise Error, "daily usage #{daily_usage.id}: #{e.class}: #{e.message}"
    end
  end

  private

  attr_reader :organization_id, :dry_run

  # Same lookup as DailyUsages::ComputeDiffService: the latest row of the subscription with the same start and an
  # earlier usage_date. The (subscription_id, usage_date) index serves it.
  def daily_usages
    scope = DailyUsage.where.not(subscription_id: nil).where(<<~SQL.squish)
      daily_usages.to_datetime <> (
        SELECT previous.to_datetime
        FROM daily_usages AS previous
        WHERE previous.subscription_id = daily_usages.subscription_id
          AND previous.from_datetime = daily_usages.from_datetime
          AND previous.usage_date < daily_usages.usage_date
        ORDER BY previous.usage_date DESC
        LIMIT 1
      )
    SQL
    scope = scope.where(organization_id:) if organization_id

    scope.includes(:subscription)
  end

  # usage_diff is the JSON string "{}" on rows that never got a snapshot
  def amount_cents(usage_diff)
    usage_diff["amount_cents"] if usage_diff.is_a?(Hash)
  end
end

namespace :migrations do
  desc "Recompute the usage_diff of the subscription daily usages whose previous row in the period ends at another " \
    "time, such as the row written at a termination. Usage: rake migrations:rechain_daily_usage_diffs[organization_id] " \
    "(omit organization_id to run for every organization). Dry run unless DRY_RUN=false."
  task :rechain_daily_usage_diffs, [:organization_id] => :environment do |_task, args|
    organization_id = args[:organization_id].presence
    if organization_id && !Organization.exists?(id: organization_id)
      abort "Organization not found. Usage: rake migrations:rechain_daily_usage_diffs[organization_id]"
    end

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"
    count = 0

    puts "Rechaining daily usage diffs [#{mode}] (organization: #{organization_id || "all"})..."

    begin
      RechainDailyUsageDiffs.call(organization_id:, dry_run:) do |entry|
        count += 1
        puts "  daily_usage=#{entry[:daily_usage_id]} organization=#{entry[:organization_id]} " \
          "subscription=#{entry[:subscription_id]} usage_date=#{entry[:usage_date].iso8601} status=#{entry[:status]} " \
          "amount_cents=#{entry[:amount_cents_before]}->#{entry[:amount_cents_after]}"
      end
    rescue RechainDailyUsageDiffs::Error => e
      abort "Stopped [#{mode}] after #{count} row(s). Failed on #{e.message}. Run the task again to resume."
    end

    puts "Done [#{mode}]. Rows #{dry_run ? "to recompute" : "recomputed"}: #{count}."
  end
end
