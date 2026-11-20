# frozen_string_literal: true

module UsageMonitoring
  module ContractAlerts
    class DestroyService < BaseService
      Result = BaseResult[:alert]

      def initialize(alert:)
        @alert = alert
        super
      end

      def call
        return result.not_found_failure!(resource: "alert") unless alert

        destroy_result = UsageMonitoring::DestroyAlertService.call(alert:)

        if destroy_result.success?
          result.alert = destroy_result.alert
          result
        else
          result.fail_with_error!(destroy_result.error)
        end
      end

      private

      attr_reader :alert
    end
  end
end
