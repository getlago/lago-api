# frozen_string_literal: true

# One-off: the hourly daily usage job skipped every other day for customers whose 0-2h local window
# falls on the previous UTC date (UTC+3 or more), and the carry-over row of a new period for their
# recurring-only subscriptions. The usage of a skipped day went into the diff of the next row.
#
# For each active subscription of such a customer, it fills the days without a row that have usage,
# then recomputes the diff of every filled row and of the row that follows one, which held the
# usage of both days. Dry run by default: nothing is written.
class RepairDailyUsageGaps
  AFFECTED_UTC_OFFSET = 3.hours

  def self.call(...) = new(...).call

  def initialize(organization_id:, from_date:, dry_run: true)
    @organization_id = organization_id
    @from_date = from_date
    @dry_run = dry_run
  end

  # One entry per subscription with at least one day without a row
  def call
    subscriptions.find_each.filter_map { process(it) }
  end

  private

  attr_reader :organization_id, :from_date, :dry_run

  def subscriptions
    Subscription.where(organization_id:).active.where(skip_daily_usage: false).includes(:plan, customer: :billing_entity)
  end

  def process(subscription)
    return unless affected?(subscription.customer.applicable_timezone)

    known_dates = usage_dates(subscription)
    missing = (first_day(subscription)..last_day(subscription)).reject { known_dates.include?(it) }
    return if missing.empty?
    return entry(subscription, status: :would_fill, days: missing) if dry_run

    DailyUsages::FillHistoryService.call!(subscription:, from_date:)

    filled = usage_dates(subscription) - known_dates
    recomputed = recompute_diffs(subscription, filled)
    entry(subscription, status: filled.any? ? :filled : :nothing_to_fill, days: filled.sort, recomputed:)
  end

  # The window was on the previous UTC date whenever the offset reached 3 hours in the range, DST included
  def affected?(timezone)
    zone = ActiveSupport::TimeZone[timezone]
    from_date.step(Date.current, 30).any? { zone.at(it.to_time(:utc)).utc_offset >= AFFECTED_UTC_OFFSET }
  end

  def first_day(subscription)
    [subscription.started_at.in_time_zone(subscription.customer.applicable_timezone).to_date, from_date].max
  end

  def last_day(subscription)
    Time.current.in_time_zone(subscription.customer.applicable_timezone).to_date - 1.day
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

  def entry(subscription, status:, days:, recomputed: [])
    {subscription_id: subscription.id, timezone: subscription.customer.applicable_timezone, status:, days:, recomputed:}
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

    from_date = begin
      args[:from_date].present? ? Date.iso8601(args[:from_date]) : DailyUsage::DEFAULT_HISTORY_DAYS.days.ago.to_date
    rescue Date::Error
      abort "Invalid from_date: #{args[:from_date]}. #{usage}"
    end

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"

    puts "Repairing daily usage gaps [#{mode}] for organization #{args[:organization_id]} from #{from_date.iso8601}..."

    report = RepairDailyUsageGaps.call(organization_id: args[:organization_id], from_date:, dry_run:)

    report.each do |entry|
      puts "  subscription=#{entry[:subscription_id]} timezone=#{entry[:timezone]} status=#{entry[:status]} " \
        "days=#{entry[:days].map(&:iso8601).join(",")} recomputed=#{entry[:recomputed].map(&:iso8601).join(",")}"
    end

    puts "Done [#{mode}]. Subscriptions with days without a daily usage: #{report.size}."
    puts "  Totals by status: #{report.map { it[:status] }.tally.map { |key, count| "#{key}=#{count}" }.join(" ")}"
  end
end
