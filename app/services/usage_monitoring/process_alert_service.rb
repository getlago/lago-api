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
      crossed_threshold_values = alert.find_thresholds_crossed(current)

      if crossed_threshold_values.present?
        record_trigger(crossed_threshold_values, current, now)
      else
        record_resolution(current, now)
      end

      alert.previous_value = current
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
