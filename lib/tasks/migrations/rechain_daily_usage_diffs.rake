# frozen_string_literal: true

# One-off: a subscription's daily usage was diffed against the earlier rows of its period that end at the same time.
# A period's end can move while its rows are written: a termination ends the last period at the termination, so the
# row written from the terminating invoice found no earlier row, and its usage_diff repeated the usage of the rows
# before it. Rows are now chained on the period start only.
#
# It recomputes the usage_diff of the rows of the periods whose rows end at several times, except the first row of
# each period. Rows written out of order (a daily job run after the termination row was written) are covered too.
# Until mid-2025 the invoice rows also ended at 23:59:59.999999 while the daily rows end at 23:59:59, so the periodic
# invoice rows of that time, of active subscriptions too, are recomputed against the daily row before them.
#
# Left as they are:
# - a row whose previous row ends at a fraction of a second: an invoice row written before mid-2025, which for a
#   pay-in-advance plan held the usage of the period before under the start of the next one;
# - a row without a stored diff (`{}`), such as the first row of a history fill.
#
# A row whose diff is already right is skipped, so a second run changes nothing. A row that cannot be diffed is
# reported and the run goes on. Dry run by default: nothing is written.
class RechainDailyUsageDiffs
  SUBSCRIPTIONS_BATCH_SIZE = 500

  def self.call(**, &) = new(**).call(&)

  def initialize(organization_id: nil, dry_run: true)
    @organization_id = organization_id
    @dry_run = dry_run
  end

  # Yields one entry per row whose diff changes or cannot be computed
  def call
    subscriptions.in_batches(of: SUBSCRIPTIONS_BATCH_SIZE) do |batch|
      candidates(batch.pluck(:id)).each do |daily_usage|
        entry = process(daily_usage)
        yield entry if entry && block_given?
      end
    end
  end

  private

  attr_reader :organization_id, :dry_run

  def subscriptions
    organization_id ? Subscription.where(organization_id:) : Subscription.all
  end

  def process(daily_usage)
    return if without_diff?(daily_usage.usage_diff)

    usage_diff = DailyUsages::ComputeDiffService.call!(daily_usage:).usage_diff
    return if usage_diff == daily_usage.usage_diff

    amount_cents_before = daily_usage.usage_diff["amount_cents"]
    daily_usage.update!(usage_diff:) unless dry_run

    entry(daily_usage, status: dry_run ? :would_recompute : :recomputed, amounts: [amount_cents_before, usage_diff["amount_cents"]])
  rescue *row_errors => e
    entry(daily_usage, status: :failed, error: "#{e.class}: #{e.message}")
  end

  # What an unexpected payload or a refused write raises. Built at run time: the app is not loaded with the rake files.
  def row_errors
    [BaseService::FailedResult, NoMethodError, TypeError, ArgumentError, ActiveRecord::ActiveRecordError]
  end

  def entry(daily_usage, status:, amounts: nil, error: nil)
    {
      daily_usage_id: daily_usage.id,
      organization_id: daily_usage.organization_id,
      subscription_id: daily_usage.subscription_id,
      usage_date: daily_usage.usage_date,
      status:,
      amount_cents_before: amounts&.first,
      amount_cents_after: amounts&.last,
      error:
    }
  end

  # usage_diff is the JSON string "{}" on rows that never got a snapshot, and {} on the first row of a history fill
  def without_diff?(usage_diff)
    usage_diff == "{}" || usage_diff == {}
  end

  # The previous row is the one ComputeDiffService diffs against: the latest row of the subscription with the same
  # start and an earlier usage_date. The (subscription_id, usage_date) index serves the lookup by subscription.
  def candidates(subscription_ids)
    ids = DailyUsage.connection.select_values(DailyUsage.sanitize_sql([<<~SQL.squish, subscription_ids:]))
      SELECT id FROM (
        SELECT
          id,
          LAG(to_datetime) OVER (PARTITION BY subscription_id, from_datetime ORDER BY usage_date) AS previous_to_datetime,
          MIN(to_datetime) OVER (PARTITION BY subscription_id, from_datetime) AS first_to_datetime,
          MAX(to_datetime) OVER (PARTITION BY subscription_id, from_datetime) AS last_to_datetime
        FROM daily_usages
        WHERE subscription_id IN (:subscription_ids) AND usage_date IS NOT NULL
      ) periods
      WHERE previous_to_datetime IS NOT NULL
        AND first_to_datetime <> last_to_datetime
        AND previous_to_datetime = date_trunc('second', previous_to_datetime)
    SQL

    DailyUsage.where(id: ids).includes(:subscription).order(:subscription_id, :from_datetime, :usage_date, :id)
  end
end

namespace :migrations do
  desc "Recompute the usage_diff of the subscription daily usages of the periods whose rows end at several times, " \
    "such as the row written at a termination. Usage: rake migrations:rechain_daily_usage_diffs[organization_id] " \
    "(omit organization_id to run for every organization). Dry run unless DRY_RUN=false."
  task :rechain_daily_usage_diffs, [:organization_id] => :environment do |_task, args|
    organization_id = args[:organization_id].presence
    if organization_id && !Organization.exists?(id: organization_id)
      abort "Organization not found. Usage: rake migrations:rechain_daily_usage_diffs[organization_id]"
    end

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"
    count = 0
    failed = 0

    puts "Rechaining daily usage diffs [#{mode}] (organization: #{organization_id || "all"})..."

    RechainDailyUsageDiffs.call(organization_id:, dry_run:) do |entry|
      line = "  daily_usage=#{entry[:daily_usage_id]} organization=#{entry[:organization_id]} " \
        "subscription=#{entry[:subscription_id]} usage_date=#{entry[:usage_date].iso8601} status=#{entry[:status]}"

      if entry[:status] == :failed
        failed += 1
        puts "#{line} error=#{entry[:error]}"
      else
        count += 1
        puts "#{line} amount_cents=#{entry[:amount_cents_before]}->#{entry[:amount_cents_after]}"
      end
    end

    puts "Done [#{mode}]. Rows #{dry_run ? "to recompute" : "recomputed"}: #{count}. Rows failed: #{failed}."
    abort "#{failed} row(s) could not be diffed: fix them, then run the task again." if failed.positive?
  end
end
