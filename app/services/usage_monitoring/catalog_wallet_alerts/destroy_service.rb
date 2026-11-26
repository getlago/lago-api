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

        ActiveRecord::Base.transaction do
          lock_wallet(wallet_of(alert))
          return result unless result.success?

          # Read again under the lock: a write that held it may have changed the alert or deleted it
          current = alert.class.lock.find_by(id: alert.id)
          return result.not_found_failure!(resource: "alert") unless current

          # Gone for good with its thresholds: the history of a contract wallet alert keeps its own copy of it
          current.destroy!
          result.alert = current
        end

        result
      end

      private

      attr_reader :alert
    end
  end
end
