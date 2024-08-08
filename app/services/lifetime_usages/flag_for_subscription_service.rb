# frozen_string_literal: true

module LifetimeUsages
  class FlagForSubscriptionService < BaseService
    def initialize(subscription:, invoiced_usage: false, current_usage: false)
      @subscription = subscription
      @invoiced_usage = invoiced_usage
      @current_usage = current_usage
      super
    end

    def call
      return result unless License.premium?
      return result.not_found_failure!(resource: 'subscription') if subscription.nil?
      # return result if subscription.plan.usage_thresholds.exists?

      result.lifetime_usage = lifetime_usage

      lifetime_usage.recalculate_invoiced_usage = true if invoiced_usage
      lifetime_usage.recalculate_current_usage = true if current_usage

      lifetime_usage.save!

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription, :invoiced_usage, :current_usage

    def lifetime_usage
      @lifetime_usage ||= LifetimeUsage.create_with(
        currency: subscription.plan.amount_currency
      ).find_or_initialize_by(
        organization_id: subscription.organization.id,
        external_subscription_id: subscription.external_id
      )
    end
  end
end
