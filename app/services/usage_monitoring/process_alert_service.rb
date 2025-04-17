# frozen_string_literal: true

module UsageMonitoring
  class ProcessAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:)
      @alert = alert
    end

    def call
      now = Time.current
      current = alert.get_current_value
      crossed_threshold_values = alert.find_thresholds_crossed(current)

      ActiveRecord::Base.transaction do
        if crossed_threshold_values.present?
          triggered_alert = TriggeredAlert.create!(
            alert:,
            organization: alert.organization,
            subscription: alert.subscription,
            current_value: current,
            previous_value: alert.previous_value,
            crossed_thresholds: alert.formatted_crossed_thresholds(crossed_threshold_values),
            triggered_at: now
          )

          after_commit { pp triggered_alert } # TODO: Job to trigger action (webhook)
        end

        alert.previous_value = current
        alert.last_processed_at = now
        alert.save!
      end
    end

    private

    attr_reader :alert
  end
end
