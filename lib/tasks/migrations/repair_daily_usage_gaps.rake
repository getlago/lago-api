# frozen_string_literal: true

# One-off: the hourly daily usage job skipped every other day for customers whose 0-2h local window
# falls on the previous UTC date (UTC+3 or more), and the carry-over row of a new period for their
# recurring-only subscriptions. The usage of a skipped day went into the diff of the next row.
#
# For each active subscription of such a customer, it fills the days without a row that have usage,
# then recomputes the diff of every filled row and of the row that follows one, which held the
# usage of both days. Each subscription is repaired in its own transaction, so a run that stops can
# be run again. A dry run (the default) does the same work and rolls it back.
#
# Left as they are: terminated subscriptions, upgraded ones included, because the backfill ends
# their last period's rows at the termination and they would not chain with the rows written
# before; rows written twice on the monthly charges billing day of yearly and semiannual plans.
# A filled day counts the events received after the next row was written, so that row's recomputed
# diff can be negative.
class RepairDailyUsageGaps
  AFFECTED_UTC_OFFSET = 3.hours
  # The hourly job writes the local yesterday in the first hours of the local day, jitter included
  HOURLY_JOB_HOURS = 4.hours

  Error = Class.new(StandardError)

  def self.call(**, &) = new(**).call(&)

  def initialize(organization_id:, from_date:, dry_run: true)
    @organization_id = organization_id
    @from_date = from_date
    @dry_run = dry_run
    @affected = Hash.new { |cache, timezone| cache[timezone] = reached_affected_offset?(timezone) }
  end

  # Yields one entry per subscription with days to fill, as soon as it is repaired
  def call
    subscriptions.find_each do |subscription|
      entry = process(subscription)
      yield entry if entry
    rescue => e
      raise Error, "subscription #{subscription.id}: #{e.class}: #{e.message}"
    end
  end

  private

  attr_reader :organization_id, :from_date, :dry_run, :affected

  def subscriptions
    Subscription.where(organization_id:).active.where(skip_daily_usage: false).includes(:plan, customer: :billing_entity)
  end

  def process(subscription)
    timezone = subscription.customer.applicable_timezone
    return unless affected[timezone]

    known_dates = usage_dates(subscription)
    last_day = last_day(timezone)
    return if (first_day(subscription, timezone)..last_day).all? { known_dates.include?(it) }

    entry = nil

    ApplicationRecord.transaction(requires_new: true) do
      DailyUsages::FillHistoryService.call!(subscription:, from_date:, to_date: last_day)

      filled = (usage_dates(subscription) - known_dates).sort
      if filled.any?
        entry = {
          subscription_id: subscription.id,
          timezone:,
          status: dry_run ? :would_fill : :filled,
          days: filled,
          recomputed: recompute_diffs(subscription, filled)
        }
      end

      raise ActiveRecord::Rollback if dry_run
    end

    entry
  end

  # The window was on the previous UTC date whenever the offset reached 3 hours in the range, DST included
  def reached_affected_offset?(timezone)
    zone = ActiveSupport::TimeZone[timezone]
    (from_date..Date.current).any? { zone.at(it.to_time(:utc)).utc_offset >= AFFECTED_UTC_OFFSET }
  end

  def first_day(subscription, timezone)
    [subscription.started_at.in_time_zone(timezone).to_date, from_date].max
  end

  # The local yesterday belongs to the hourly job until its window is over
  def last_day(timezone)
    (Time.current.in_time_zone(timezone) - HOURLY_JOB_HOURS).to_date - 1.day
  end

  def usage_dates(subscription)
    subscription.daily_usages.where(usage_date: from_date..).pluck(:usage_date).to_set
  end

  def recompute_diffs(subscription, filled)
    rows = subscription.daily_usages.where(usage_date: from_date..).order(:from_datetime, :usage_date)

    rows.group_by(&:from_datetime).values.flat_map do |period_rows|
      [nil, *period_rows].each_cons(2).filter_map do |previous, current|
        next unless [previous, current].compact.any? { filled.include?(it.usage_date) }

        current.update!(usage_diff: DailyUsages::ComputeDiffService.call!(daily_usage: current).usage_diff)
        current.usage_date
      end
    end
  end
end

namespace :migrations do
  desc "Fill the daily usages skipped for customers at UTC+3 or more and recompute the diffs around them. " \
    "Usage: rake migrations:repair_daily_usage_gaps[organization_id,from_date] " \
    "(from_date defaults to the daily usage history depth). Dry run unless DRY_RUN=false."
  task :repair_daily_usage_gaps, [:organization_id, :from_date] => :environment do |_task, args|
    usage = "Usage: rake migrations:repair_daily_usage_gaps[organization_id,from_date]"
    abort usage if args[:organization_id].blank?
    abort "Organization not found. #{usage}" unless Organization.exists?(id: args[:organization_id])

    # Only the hourly job and the invoices of these organizations keep daily usages up to date
    unless Organization.with_revenue_analytics_support.exists?(id: args[:organization_id])
      abort "Revenue analytics is not enabled for this organization: its daily usages are not kept up to date."
    end

    from_date = begin
      args[:from_date].present? ? Date.iso8601(args[:from_date]) : DailyUsage::DEFAULT_HISTORY_DAYS.days.ago.to_date
    rescue Date::Error
      abort "Invalid from_date: #{args[:from_date]}. #{usage}"
    end

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"
    count = 0

    puts "Repairing daily usage gaps [#{mode}] for organization #{args[:organization_id]} from #{from_date.iso8601}..."

    begin
      RepairDailyUsageGaps.call(organization_id: args[:organization_id], from_date:, dry_run:) do |entry|
        count += 1
        puts "  subscription=#{entry[:subscription_id]} timezone=#{entry[:timezone]} status=#{entry[:status]} " \
          "days=#{entry[:days].map(&:iso8601).join(",")} recomputed=#{entry[:recomputed].map(&:iso8601).join(",")}"
      end
    rescue RepairDailyUsageGaps::Error => e
      abort "Stopped [#{mode}] after #{count} subscription(s). Failed on #{e.message}. " \
        "Its changes were rolled back: run the task again to resume."
    end

    puts "Done [#{mode}]. Subscriptions #{dry_run ? "to repair" : "repaired"}: #{count}."
  end
end
