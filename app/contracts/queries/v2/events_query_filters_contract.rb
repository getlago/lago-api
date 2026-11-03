# frozen_string_literal: true

module Queries
  module V2
    class EventsQueryFiltersContract < Dry::Validation::Contract
      params do
        optional(:code).maybe(:string)
        optional(:transaction_id).maybe(:string)
        optional(:external_contract_id).maybe(:string)
        optional(:external_subscription_id).maybe(:string)
        optional(:timestamp_from_started_at).value(:"coercible.string", included_in?: %w[true false])
        optional(:timestamp_from)
        optional(:timestamp_to)
        optional(:created_at_from)
        optional(:created_at_to)
      end

      rule(:timestamp_from_started_at, :timestamp_from) do
        if values[:timestamp_from_started_at] == "true" && values[:timestamp_from].present?
          key(:timestamp_from).failure("cannot be used with timestamp_from_started_at")
        end
      end

      rule(:timestamp_from_started_at, :external_contract_id, :external_subscription_id) do
        if values[:timestamp_from_started_at] == "true" && values[:external_contract_id].blank? && values[:external_subscription_id].blank?
          key(:external_contract_id).failure("required with timestamp_from_started_at")
        end
      end
    end
  end
end
