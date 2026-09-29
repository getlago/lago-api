# frozen_string_literal: true

module UsageMonitoring
  class DestroyAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:)
      @alert = alert
      super
    end

    def call
      return result.not_found_failure!(resource: "alert") unless alert

      alert.with_lock do
        alert.thresholds.delete_all
        alert.discard!
      end

      result.alert = alert
      result
    end

    private

    attr_reader :alert
  end
end
