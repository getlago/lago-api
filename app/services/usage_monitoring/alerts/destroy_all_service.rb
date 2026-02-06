# frozen_string_literal: true

module UsageMonitoring
  module Alerts
    class DestroyAllService < BaseService
      Result = BaseResult[:alerts]

      def initialize(organization:, subscription:)
        @organization = organization
        @subscription = subscription
        super
      end

      def call
        return result.not_found_failure!(resource: "organization") unless organization
        return result.not_found_failure!(resource: "subscription") unless subscription

        alert_ids = organization.alerts.where(subscription_external_id: subscription.external_id).ids
        ActiveRecord::Base.transaction do
          AlertThreshold.where(usage_monitoring_alert_id: alert_ids).delete_all
          Alert.where(id: alert_ids).update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        end

        result
      end

      private

      attr_reader :organization, :subscription
    end
  end
end
