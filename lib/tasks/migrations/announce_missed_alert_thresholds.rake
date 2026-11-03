# frozen_string_literal: true

# One-off: announces the thresholds that subscription usage alerts had already passed when they started from their
# usage at creation (alerts created between the creation baseline and its removal): those lines were stored as
# previous_value and never produced an alert.triggered.
#
# For each alert of the creation window, it records one triggered row and sends one alert.triggered from 0 up to
# the stored previous_value, minus the lines already announced. The alert itself is never changed, so the next
# regular evaluation goes on from the same previous_value. Dry run by default: nothing is written or sent.
class AnnounceMissedAlertThresholds
  # Creation inserts the thresholds in the alert's transaction; only an edit gives them a later timestamp
  THRESHOLDS_EDIT_TOLERANCE = 1.minute

  def self.call(...) = new(...).call

  def initialize(from:, to:, organization_id: nil, dry_run: true)
    @from = from
    @to = to
    @organization_id = organization_id
    @dry_run = dry_run
  end

  # One entry per alert of the window, with its status and the thresholds announced or the skip reason
  def call
    alerts.find_each.map { process(it) }
  end

  private

  attr_reader :from, :to, :organization_id, :dry_run

  def alerts
    scope = UsageMonitoring::Alert.using_subscription.where(created_at: from..to)

    if organization_id.present?
      scope.where(organization_id:)
    else
      scope
    end
  end

  def process(alert)
    alert.with_lock do
      subscription = active_subscription(alert)
      reason = skip_reason(alert, subscription)
      next entry(alert, status: :skipped, reason:) if reason

      missed = missed_thresholds(alert)
      if missed.empty?
        entry(alert, status: :skipped, reason: below_or_announced(alert))
      elsif dry_run
        entry(alert, status: :would_announce, thresholds: missed)
      else
        announce(alert, subscription, missed)
        entry(alert, status: :announced, thresholds: missed)
      end
    end
  end

  def skip_reason(alert, subscription)
    # The alert can be deleted between the scope and the lock: deletion does not take the lock
    if alert.discarded?
      :discarded
    elsif alert.last_processed_at.nil?
      :never_evaluated
    elsif subscription.nil?
      :no_active_subscription
    elsif thresholds_edited?(alert)
      :thresholds_edited
    elsif period_ended?(alert, subscription)
      :period_ended
    end
  end

  def active_subscription(alert)
    alert.organization.subscriptions.active.find_by(external_id: alert.subscription_external_id)
  end

  def thresholds_edited?(alert)
    alert.thresholds.any? { it.created_at > alert.created_at + THRESHOLDS_EDIT_TOLERANCE }
  end

  # The regular evaluation announces again from 0 once a resetting window renews, so the lines missed in an
  # ended period are no longer due. Lifetime alerts and other current usage ones keep their baseline across
  # renewals: only current usage alert types can reset their window. The window is the charges period, the
  # start the regular evaluation resets on (monthly charges of a yearly plan renew each month).
  def period_ended?(alert, subscription)
    return false unless alert.window_resets_each_period?(subscription)

    period_start = Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)
      .charges_from_datetime
    period_start > alert.created_at || alert.last_processed_at < period_start
  end

  def crossed_from_zero(alert)
    alert.find_thresholds_crossed(alert.previous_value, previous: 0)
  end

  def missed_thresholds(alert)
    highest_announced = alert.triggered_alerts.maximum(:current_value)
    crossed = crossed_from_zero(alert)

    if highest_announced
      crossed.reject { it <= highest_announced }
    else
      crossed
    end
  end

  # A triggered row announced the lines between its previous and current value. A line no row covers was
  # left out because a regular evaluation already announced a higher one.
  def below_or_announced(alert)
    crossed = crossed_from_zero(alert)
    return :below_thresholds if crossed.empty?

    ranges = alert.triggered_alerts.pluck(:previous_value, :current_value)
    if crossed.all? { |line| ranges.any? { |from, to| line > from && line <= to } }
      :already_announced
    else
      :higher_threshold_announced
    end
  end

  def announce(alert, subscription, missed)
    triggered_alert = UsageMonitoring::TriggeredAlert.create!(
      alert:,
      organization: alert.organization,
      alertable: subscription,
      current_value: alert.previous_value,
      previous_value: 0,
      crossed_thresholds: alert.formatted_crossed_thresholds(missed),
      triggered_at: Time.current
    )

    SendWebhookJob.perform_after_commit("alert.triggered", triggered_alert)
  end

  def entry(alert, status:, reason: nil, thresholds: [])
    {
      alert_id: alert.id,
      organization_id: alert.organization_id,
      alert_type: alert.alert_type,
      alert_code: alert.code,
      status:,
      reason:,
      previous_value: alert.previous_value,
      thresholds:
    }
  end
end

namespace :migrations do
  desc "Announce the thresholds that subscription usage alerts passed before their creation baseline. " \
    "Usage: rake migrations:announce_missed_alert_thresholds[from,to,organization_id] " \
    "(from and to filter on the alert created_at; omit organization_id to run for every organization). " \
    "Dry run unless DRY_RUN=false."
  task :announce_missed_alert_thresholds, [:from, :to, :organization_id] => :environment do |_task, args|
    usage = "Usage: rake migrations:announce_missed_alert_thresholds[from,to,organization_id]"
    abort usage if args[:from].blank? || args[:to].blank?

    from, to = [args[:from], args[:to]].map do |value|
      Time.zone.parse(value) || abort("Invalid from or to: #{value}. #{usage}")
    rescue ArgumentError
      abort "Invalid from or to: #{value}. #{usage}"
    end
    abort "from must be before to. #{usage}" if from > to

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"
    organization_id = args[:organization_id].presence

    puts "Announcing missed alert thresholds [#{mode}] for alerts created from #{from.iso8601} to #{to.iso8601} " \
      "(organization: #{organization_id || "all"})..."

    report = AnnounceMissedAlertThresholds.call(from:, to:, organization_id:, dry_run:)

    report.each do |entry|
      line = "  alert=#{entry[:alert_id]} organization=#{entry[:organization_id]} type=#{entry[:alert_type]} " \
        "code=#{entry[:alert_code]} status=#{entry[:status]} previous_value=#{entry[:previous_value].to_s("F")} " \
        "thresholds=#{entry[:thresholds].map { it.to_s("F") }.join(",")}"
      reason = entry[:reason] ? " reason=#{entry[:reason]}" : ""
      puts "#{line}#{reason}"
    end

    format_totals = ->(values) { values.tally.map { |key, count| "#{key}=#{count}" }.join(" ") }

    puts "Done [#{mode}]. Alerts considered: #{report.size}."
    puts "  Totals by status: #{format_totals.call(report.map { it[:status] })}"
    puts "  Totals by skip reason: #{format_totals.call(report.filter_map { it[:reason] })}"
  end
end
