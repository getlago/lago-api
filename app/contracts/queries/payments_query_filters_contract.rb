# frozen_string_literal: true

module Queries
  class PaymentsQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:invoice_id).maybe(:string, format?: Regex::UUID)
      optional(:external_customer_id).maybe(:string)
      optional(:currency).maybe(:string, included_in?: Currencies::ACCEPTED_CURRENCIES.keys.map(&:to_s))
      optional(:amount_from).maybe(:integer, gteq?: 0, lteq?: 9_223_372_036_854_775_807)
      optional(:amount_to).maybe(:integer, gteq?: 0, lteq?: 9_223_372_036_854_775_807)
      optional(:receipt_number).maybe(:string, max_size?: 255)
      optional(:invoice_number).maybe(:string, max_size?: 255)

      optional(:payment_status).maybe do
        value(:string, included_in?: Payment::PAYABLE_PAYMENT_STATUS) |
          array(:string, included_in?: Payment::PAYABLE_PAYMENT_STATUS)
      end
      optional(:payment_provider_type).maybe do
        value(:string, included_in?: Customer::PAYMENT_PROVIDERS) |
          array(:string, included_in?: Customer::PAYMENT_PROVIDERS)
      end
      optional(:payment_method_type).maybe do
        value(:string, included_in?: PaymentMethod::PROVIDER_METHOD_TYPES) |
          array(:string, included_in?: PaymentMethod::PROVIDER_METHOD_TYPES)
      end
      optional(:payment_type).maybe do
        value(:string, included_in?: Payment::PAYMENT_TYPES.keys.map(&:to_s)) |
          array(:string, included_in?: Payment::PAYMENT_TYPES.keys.map(&:to_s))
      end
      optional(:payable_type).maybe do
        value(:string, included_in?: Payment::PAYABLE_TYPES) |
          array(:string, included_in?: Payment::PAYABLE_TYPES)
      end
    end

    rule(:amount_from, :amount_to) do
      if values[:amount_from] && values[:amount_to] && values[:amount_from] > values[:amount_to]
        key(:amount_to).failure("must be greater than or equal to amount_from")
      end
    end
  end
end
