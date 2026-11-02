# frozen_string_literal: true

# Announces the thresholds that subscription usage alerts had already passed when they started from their usage
# at creation: those lines were stored as previous_value and never produced an alert.triggered.
#
# For each alert of the creation window, it records one triggered row and sends one alert.triggered from 0 up to
# the stored previous_value, minus the lines already announced. The alert itself is never changed, so the next
# regular evaluation goes on from the same previous_value. Dry run by default: nothing is written or sent.
module UsageMonitoring
  class AnnounceMissedThresholdsService < BaseService
    Result = BaseResult[:report]

    # Creation inserts the thresholds in the alert's transaction; only an edit gives them a later timestamp
    THRESHOLDS_EDIT_TOLERANCE = 1.minute

    def initialize(from:, to:, organization_id: nil, dry_run: true)
      @from = from
      @to = to
      @organization_id = organization_id
      @dry_run = dry_run
      super
    end

    def call
      result.report = alerts.find_each.map { process(it) }
      result
    end

    private

    attr_reader :from, :to, :organization_id, :dry_run

    def alerts
      scope = Alert.using_subscription.where(created_at: from..to)

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
    # ended period are no longer due. Other alerts keep their baseline across renewals.
    def period_ended?(alert, subscription)
      return false unless Alert::CURRENT_USAGE_TYPES.include?(alert.alert_type)
      return false unless alert.window_resets_each_period?(subscription)

      period_start = Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true).from_datetime
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

    def below_or_announced(alert)
      crossed_from_zero(alert).empty? ? :below_thresholds : :already_announced
    end

    def announce(alert, subscription, missed)
      triggered_alert = TriggeredAlert.create!(
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
end
