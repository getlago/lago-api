# frozen_string_literal: true

module DunningCampaigns
  class BulkProcessService < BaseService
    Result = BaseResult

    BATCH_SIZE = 1_000

    def call
      return result unless License.premium?

      # Run the eligibility query once, then load customers by primary key.
      # find_each would re-run the full query for every batch.
      eligible_customers.pluck(:id).each_slice(BATCH_SIZE) do |ids|
        Customer.where(id: ids).find_each do |customer|
          DunningCampaigns::ProcessCustomerJob.perform_later(customer)
        end
      end

      result
    end

    private

    # Mirrors the early returns of ProcessCustomerService so that only customers
    # who can actually be dunned get a job. ProcessCustomerService keeps its own
    # checks as a safety net.
    def eligible_customers
      Customer
        .joins(:organization)
        .joins(
          <<~SQL.squish
            LEFT JOIN dunning_campaigns customer_campaigns
              ON customer_campaigns.id = customers.applied_dunning_campaign_id
              AND customer_campaigns.deleted_at IS NULL
            LEFT JOIN billing_entities
              ON billing_entities.id = customers.billing_entity_id
              AND billing_entities.deleted_at IS NULL
            LEFT JOIN dunning_campaigns billing_entity_campaigns
              ON billing_entity_campaigns.id = billing_entities.applied_dunning_campaign_id
              AND billing_entity_campaigns.deleted_at IS NULL
          SQL
        )
        .where(exclude_from_dunning_campaign: false)
        .where("organizations.premium_integrations @> ARRAY[?]::varchar[]", ["auto_dunning"])
        .where("COALESCE(customer_campaigns.id, billing_entity_campaigns.id) IS NOT NULL")
        .where(
          <<~SQL.squish,
            customers.last_dunning_campaign_attempt_at IS NULL
            OR customers.last_dunning_campaign_attempt_at
              + make_interval(days => COALESCE(customer_campaigns.days_between_attempts, billing_entity_campaigns.days_between_attempts))
              < :now
          SQL
          now: Time.current
        )
        .where(
          id: Invoice.where(payment_overdue: true, self_billed: false)
            .select(:customer_id)
        )
    end
  end
end
