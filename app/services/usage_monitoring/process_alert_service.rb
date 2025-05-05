# frozen_string_literal: true

module UsageMonitoring
  class ProcessAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:, subscription:, current_metrics:)
      @alert = alert
      @subscription = subscription
      @current_metrics = current_metrics
      super
    end

    def call
      now = Time.current
      current = alert.find_value(current_metrics)
      crossed_threshold_values = alert.find_thresholds_crossed(current)

      ActiveRecord::Base.transaction do
        if crossed_threshold_values.present?
          triggered_alert = TriggeredAlert.create!(
            alert:,
            organization: alert.organization,
            subscription: subscription,
            current_value: current,
            previous_value: alert.previous_value,
            crossed_thresholds: alert.formatted_crossed_thresholds(crossed_threshold_values),
            triggered_at: now
          )

          after_commit { SendWebhookJob.perform_later("alert.triggered", triggered_alert) }
        end

        alert.previous_value = current
        alert.last_processed_at = now
        alert.save!
      end

      result.alert = alert
      result
    end

    private

    attr_reader :alert, :subscription, :current_metrics
  end
end
