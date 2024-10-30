# frozen_string_literal: true

module DunningCampaigns
  class BulkProcessService < BaseService
    # Find all eligible customers
    # Find applicable dunning campaign
    # next step?
    # Queue job for next step; customer, campaign

    def call
      return result unless License.premium?

      eligible_customers.find_each do |customer|
        dunning_campaign_threshold = find_applicable_dunning_campaign_threshold(customer)
        dunning_campaign = dunning_campaign_threshold.dunning_campaign

        next unless dunning_campaign_threshold
        next if max_attempts_reached?(customer, dunning_campaign)
        next unless days_between_attempts_satisfied?(customer, dunning_campaign)

        DunningCampaigns::ProcessAttemptJob.perform_later(
          customer:,
          dunning_campaign_threshold:
        )
      end

      result
    end

    private

    def eligible_customers
      Customer
        .joins(:organization)
        .where("organizations.premium_integrations @> ARRAY[?]::varchar[]", ['auto_dunning'])
    end

    def find_applicable_dunning_campaign_threshold(customer)
      dunning_campaign = find_dunning_campaign(customer)

      dunning_campaign
        .thresholds
        .where(currency: customer.currency)
        .find_by("amount_cents <= ?", customer.overdue_balance_cents)
    end

    def find_dunning_campaign(customer)
      organization = customer.organization

      customer.applied_dunning_campaign || organization.applied_dunning_campaign
    end

    def max_attempts_reached?(customer, dunning_campaign)
      customer.last_dunning_campaign_attempt >= dunning_campaign.max_attempts
    end

    def days_between_attempts_satisfied?(customer, dunning_campaign)
      return true unless customer.last_dunning_campaign_attempt_at

      next_attempt_date = customer.last_dunning_campaign_attempt_at + dunning_campaign.days_between_attempts.days

      Time.zone.now >= next_attempt_date
    end
  end
end
