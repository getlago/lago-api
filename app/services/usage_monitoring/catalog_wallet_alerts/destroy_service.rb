# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    class DestroyService < BaseService
      Result = BaseResult[:alert]

      def initialize(alert:)
        @alert = alert
        super
      end

      def call
        return result.not_found_failure!(resource: "alert") unless alert

        # Template writes lock the plan wallet, so a contract copying its templates sees one version of them
        alert.plan_wallet.with_lock do
          return result.not_found_failure!(resource: "plan_wallet") if alert.plan_wallet.discarded?

          # Read again under the lock: a write that held it may have changed the template or deleted it
          template = PlanWalletAlert.find_by(id: alert.id)
          return result.not_found_failure!(resource: "alert") unless template

          template.destroy!
          result.alert = template
        end

        result
      end

      private

      attr_reader :alert
    end
  end
end
