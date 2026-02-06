# frozen_string_literal: true

module UsageMonitoring
  class DestroyAllAlertsService < BaseService
    Result = BaseResult[:alerts]

    def initialize(organization:, subscription:)
      @organization = organization
      @subscription = subscription
      super
    end

    def call
      alerts = organization.alerts.where(subscription_external_id: subscription.external_id).to_a

      ActiveRecord::Base.transaction do
        alerts.each do |alert|
          alert.thresholds.delete_all
          alert.discard!
        end
      end

      result.alerts = alerts
      result
    end

    private

    attr_reader :organization, :subscription
  end
end
