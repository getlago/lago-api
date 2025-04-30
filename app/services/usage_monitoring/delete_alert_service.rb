# frozen_string_literal: true

module UsageMonitoring
  class DeleteAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:)
      @alert = alert
      super
    end

    def call
      ActiveRecord::Base.transaction do
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
