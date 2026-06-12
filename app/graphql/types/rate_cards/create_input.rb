# frozen_string_literal: true

module Types
  module RateCards
    class CreateInput < BaseInputObject
      description "Create rate card input arguments"

      argument :code, String, required: true
      argument :name, String, required: true
      argument :product_item_id, ID, required: true

      argument :applied_pricing_unit_code, String, required: false
      argument :billing_timing, Types::RateCards::BillingTimingEnum, required: false
      argument :currency, Types::CurrencyEnum, required: true
      argument :description, String, required: false
      argument :display_on_invoice, Boolean, required: false
      argument :product_item_filter_id, ID, required: false
      argument :proration, Types::RateCards::ProrationEnum, required: false
      argument :rates, [Types::RateCardRates::Input], required: false
      argument :regroup_paid_fees, Types::RateCards::RegroupPaidFeesEnum, required: false
      argument :wallet_targetable, Boolean, required: false
    end
  end
end
