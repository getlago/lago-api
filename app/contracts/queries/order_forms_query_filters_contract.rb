# frozen_string_literal: true

module Queries
  class OrderFormsQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:status).maybe do
        value(:string, included_in?: OrderForm::STATUSES.keys.map(&:to_s)) |
          array(:string, included_in?: OrderForm::STATUSES.keys.map(&:to_s))
      end
      optional(:external_customer_id).maybe do
        value(:string) | array(:string)
      end
      optional(:number).maybe do
        value(:string) | array(:string)
      end
      optional(:customer_id).maybe do
        value(:string, format?: Regex::UUID) | array(:string, format?: Regex::UUID)
      end
      optional(:owner_id).maybe do
        value(:string, format?: Regex::UUID) | array(:string, format?: Regex::UUID)
      end
      optional(:quote_number).maybe do
        value(:string) | array(:string)
      end
      optional(:order_form_date_from).maybe(:time)
      optional(:order_form_date_to).maybe(:time)
      optional(:expiry_date_from).maybe(:time)
      optional(:expiry_date_to).maybe(:time)
    end
  end
end
