# frozen_string_literal: true

module DunningCampaigns
  class BulkProcessService < BaseService
    def call
      return result unless License.premium?

      eligible_customers.find_each do |customer|
        CustomerDunningEvaluator.call(customer)
      end

      result
    end

    private

    def eligible_customers
      Customer
        .joins(:organization)
        .where(exclude_from_dunning_campaign: false)
        .where("organizations.premium_integrations @> ARRAY[?]::varchar[]", ["auto_dunning"])
        .where(
          id: Invoice.where(payment_overdue: true, self_billed: false)
            .select(:customer_id)
        )
    end

    class CustomerDunningEvaluator < BaseService
      def initialize(customer)
        @customer = customer
        @billing_entity = customer.billing_entity
        @dunning_campaign = applicable_dunning_campaign
      end

      def call
        return result unless dunning_campaign
        return result unless days_between_attempts_satisfied?
        return result if max_attempts_reached?

        applicable_dunning_campaign_thresholds.each do |threshold|
          DunningCampaigns::ProcessAttemptJob.perform_later(customer:, dunning_campaign_threshold: threshold)
        end

        result
      end

      private

      attr_reader :customer, :dunning_campaign, :billing_entity

      def applicable_dunning_campaign
        customer.applied_dunning_campaign || billing_entity.applied_dunning_campaign
      end

      def applicable_dunning_campaign_thresholds
        customer.overdue_balances.filter_map do |currency, amount_cents|
          dunning_campaign
            .thresholds
            .where(currency:)
            .find_by("amount_cents <= ?", amount_cents)
        end
      end

      def max_attempts_reached?
        customer.last_dunning_campaign_attempt >= dunning_campaign.max_attempts
      end

      def days_between_attempts_satisfied?
        return true unless customer.last_dunning_campaign_attempt_at

        next_attempt_date = customer.last_dunning_campaign_attempt_at + dunning_campaign.days_between_attempts.days

        Time.zone.now >= next_attempt_date
      end
    end
  end
end
