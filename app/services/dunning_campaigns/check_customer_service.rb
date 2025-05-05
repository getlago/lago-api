# frozen_string_literal: true

module DunningCampaigns
  class CheckCustomerService < BaseService
    Result = BaseResult[:should_process_customer, :customer, :threshold]

    def initialize(customer:)
      @customer = customer
      @organization = customer.organization
      @dunning_campaign = applicable_dunning_campaign
      @threshold = applicable_dunning_campaign_threshold

      super()
    end

    def call
      result.should_process_customer = false
      result.customer = customer
      result.threshold = threshold

      return result unless threshold
      return result if max_attempts_reached?
      return result unless days_between_attempts_satisfied?

      result.should_process_customer = true
      result
    end

    private

    attr_reader :customer, :dunning_campaign, :threshold, :organization

    def applicable_dunning_campaign
      customer.applied_dunning_campaign || organization.applied_dunning_campaign
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
  end
end
