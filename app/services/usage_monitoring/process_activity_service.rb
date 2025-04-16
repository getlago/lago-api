# frozen_string_literal: true

module UsageMonitoring
  class ProcessActivityService < BaseService
    Result = BaseResult

    def initialize(organization:, subscription_external_id:)
      @organization = organization
      @subscription_external_id = subscription_external_id
    end

    def call
      # What if we stored the customer_id in the Alert table :think:
      subscription = organization
        .subscriptions
        .active
        .order(started_at: :desc)
        .find_by(external_id: subscription_external_id)

      Alert.where(subscription_external_id:, organization:).find_each do |alert|
        # TODO: will be a dedicated job

        # TODO: move to model subscription will be load multipe times
        current = if alert.is_a? UsageMonitoring::UsageAmountAlert
          get_current_usage(subscription, alert.billable_metric)
        else
          raise NotImplementedError
        end

        crossed_threshold = alert.find_thresholds_crossed(current)

        ActiveRecord::Base.transaction do
          alert.previous_value = current

          pps(crossed_threshold:)

          # alert.prev_updated_at = Time.current
          # if crossed_threshold.present?
          #   AlertHistory.create!(alert, current, prev threshold, organization)
          #   after_commit { send_alert_history }
          # end
        end
      end

      result
    end

    private

    attr_reader :organization, :subscription_external_id

    def get_current_usage(subscription, i1)
      result = ::Invoices::CustomerUsageService.call(customer: subscription.customer, subscription:, apply_taxes: false)
      result.usage.amount_cents
    end
  end
end
