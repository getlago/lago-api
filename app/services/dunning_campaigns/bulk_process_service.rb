# frozen_string_literal: true

module DunningCampaigns
  class BulkProcessService < BaseService
    Result = BaseResult

    def call
      return result unless License.premium?

      eligible_customers.select(:id).find_each do |customer|
        DunningCampaigns::ProcessCustomerJob.perform_later(customer)
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
  end
end
