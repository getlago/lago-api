# frozen_string_literal: true

module UsageMonitoring
  class ProcessAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:)
      @alert = alert
    end

    def call
      current = alert.get_current_value
      crossed_threshold = alert.find_thresholds_crossed(current)

      ActiveRecord::Base.transaction do
        alert.previous_value = current
        alert.last_processed_at = Time.current
        alert.save!

        pps(crossed_threshold:)

        # if crossed_threshold.present?
        #   AlertHistory.create!(alert, current, prev threshold, organization)
        #   after_commit { send_alert_history }
        # end
      end
    end

    private

    attr_reader :alert
  end
end
