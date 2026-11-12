# frozen_string_literal: true

module RateCardRates
  class ApplyRateChangeJob < ApplicationJob
    queue_as :default
    unique :until_executing, on_conflict: :log

    def perform(rate_card_rate_id)
      rate = RateCardRate.find_by(id: rate_card_rate_id)
      return unless rate
      return unless rate.rate_card.kept? && rate.rate_card.product.fixed?

      contract_ids = rate.rate_card.contract_applied_rate_cards
        .where(organization_id: rate.organization_id).select(:contract_id)
      customer_ids = rate.organization.contracts.active.where(id: contract_ids).select(:customer_id)
      rate.organization.customers.where(id: customer_ids).find_each do |customer|
        BillingOperations::ApplyRateChangeJob.perform_later(customer.id, rate.id)
      end
    end
  end
end
