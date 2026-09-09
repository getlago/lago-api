# frozen_string_literal: true

module UsageMonitoring
  class ProcessAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:, current_metrics:, alertable:)
      @alert = alert
      @alertable = alertable
      @current_metrics = current_metrics
      super
    end

    def call
      now = Time.current

      alert.with_lock do
        # NOTE: read inside the lock so the metric selection and the thresholds come from the same configuration
        current = alert.find_value(current_metrics)

        # NOTE: current is nil if the alert is set for a billable metric which is not part of any charges of the plan
        evaluate(current, now) unless current.nil?

        alert.last_processed_at = now
        alert.save!
      end

      result.alert = alert
      result
    end

    private

    attr_reader :alert, :alertable, :current_metrics

    def evaluate(current, now)
      # Re-baselining discards the evidence a recovery would be measured against, so it replaces the resolution.
      rebaselined = period_rolled_over? && alert.window_resets_each_period?(alertable)
      alert.previous_value = 0 if rebaselined

      crossed_threshold_values = alert.find_thresholds_crossed(current)

      if crossed_threshold_values.present?
        record_trigger(crossed_threshold_values, current, now)
      elsif !rebaselined
        record_resolution(current, now)
      end

      alert.previous_value = current
    end

    def period_rolled_over?
      return false unless Alert::CURRENT_USAGE_TYPES.include?(alert.alert_type)
      return false if alert.last_processed_at.nil?

      # NOTE: from_datetime arrives as an ISO8601 string on the usage path, hence the parse
      alert.last_processed_at < Time.zone.parse(current_metrics.from_datetime.to_s)
    end

    def record_trigger(crossed_threshold_values, current, now)
      triggered_alert = TriggeredAlert.create!(
        alert:,
        organization: alert.organization,
        alertable:,
        current_value: current,
        previous_value: alert.previous_value,
        crossed_thresholds: alert.formatted_crossed_thresholds(crossed_threshold_values),
        triggered_at: now
      )

      after_commit { SendWebhookJob.perform_later("alert.triggered", triggered_alert) }
    end

    def record_resolution(current, now)
      recovered_values = alert.find_thresholds_recovered(current)
      return if recovered_values.empty?

      recorded = alert.recorded_alarm_codes
      announced = alert.opted_in_thresholds.filter { recovered_values.include?(it.value) && recorded.include?(it.code) }
      return if announced.empty?

      TriggeredAlert.create!(
        alert:,
        organization: alert.organization,
        alertable:,
        kind: :resolved,
        current_value: current,
        previous_value: alert.previous_value,
        crossed_thresholds: alert.formatted_crossed_thresholds(announced.map(&:value)),
        in_alarm_thresholds: alert.in_alarm_threshold_codes(current),
        fully_resolved: alert.fully_resolved?(current),
        triggered_at: now
      )
    end
  end
end
