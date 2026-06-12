# frozen_string_literal: true

module Types
  module RateCards
    class UpdateInput < BaseInputObject
      description "Update rate card input arguments"

      argument :id, ID, required: true

      argument :applied_pricing_unit_code, String, required: false
      argument :billing_timing, Types::RateCards::BillingTimingEnum, required: false
      argument :currency, Types::CurrencyEnum, required: false
      argument :description, String, required: false
      argument :display_on_invoice, Boolean, required: false
      argument :name, String, required: false
      argument :proration, Types::RateCards::ProrationEnum, required: false
      argument :regroup_paid_fees, Types::RateCards::RegroupPaidFeesEnum, required: false
      argument :wallet_targetable, Boolean, required: false
    end
  end
end
