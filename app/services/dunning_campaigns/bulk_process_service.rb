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
    end

    class CustomerDunningEvaluator < BaseService
      def initialize(customer)
        @customer = customer
        @billing_entity = customer.billing_entity
        @dunning_campaign = applicable_dunning_campaign
        @threshold = applicable_dunning_campaign_threshold
      end

      def call
        return result unless threshold
        return send_campaign_finished_webhook if max_attempts_reached?
        return result unless days_between_attempts_satisfied?

        DunningCampaigns::ProcessAttemptJob.perform_later(customer:, dunning_campaign_threshold: threshold)

        result
      end

      private

      attr_reader :customer, :dunning_campaign, :threshold, :billing_entity

      def applicable_dunning_campaign
        customer.applied_dunning_campaign || billing_entity.applied_dunning_campaign
      end

      def applicable_dunning_campaign_threshold
        return unless dunning_campaign

        dunning_campaign
          .thresholds
          .where(currency: customer.currency)
          .find_by("amount_cents <= ?", customer.overdue_balance_cents)
      end

      def max_attempts_reached?
        customer.last_dunning_campaign_attempt >= dunning_campaign.max_attempts
      end

      def days_between_attempts_satisfied?
        return true unless customer.last_dunning_campaign_attempt_at

        next_attempt_date = customer.last_dunning_campaign_attempt_at + dunning_campaign.days_between_attempts.days

        Time.zone.now >= next_attempt_date
      end

      def send_campaign_finished_webhook
        SendWebhookJob.perform_later(
          "dunning_campaign.finished",
          customer,
          dunning_campaign_code: dunning_campaign.code
        )

        result
      end
    end
  end
end
