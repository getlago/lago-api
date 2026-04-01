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

        thresholds = applicable_dunning_campaign_thresholds
        return result if thresholds.empty?

        increment_per_currency_attempts(thresholds)

        thresholds.each do |threshold|
          DunningCampaigns::ProcessAttemptJob.perform_later(customer:, dunning_campaign_threshold: threshold)
        end

        if applicable_dunning_campaign_thresholds.empty?
          SendWebhookJob.perform_later(
            "dunning_campaign.finished",
            customer,
            dunning_campaign_code: dunning_campaign.code
          )
        end

        result
      end

      private

      attr_reader :customer, :dunning_campaign, :billing_entity

      def applicable_dunning_campaign
        customer.applied_dunning_campaign || billing_entity.applied_dunning_campaign
      end

      def applicable_dunning_campaign_thresholds
        attempts = customer.dunning_currency_attempts
        customer.overdue_balances.filter_map do |currency, amount_cents|
          next if (attempts[currency] || 0) >= dunning_campaign.max_attempts

          dunning_campaign
            .thresholds
            .where(currency:)
            .find_by("amount_cents <= ?", amount_cents)
        end
      end

      def increment_per_currency_attempts(thresholds)
        attempts = customer.dunning_currency_attempts.dup
        thresholds.each do |threshold|
          attempts[threshold.currency] = (attempts[threshold.currency] || 0) + 1
        end
        customer.dunning_currency_attempts = attempts
        customer.last_dunning_campaign_attempt_at = Time.zone.now
        customer.save!
      end

      def days_between_attempts_satisfied?
        return true unless customer.last_dunning_campaign_attempt_at

        next_attempt_date = customer.last_dunning_campaign_attempt_at + dunning_campaign.days_between_attempts.days

        Time.zone.now >= next_attempt_date
      end
    end
  end
end
