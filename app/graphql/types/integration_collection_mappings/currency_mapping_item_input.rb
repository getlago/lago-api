# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module IntegrationCollectionMappings
    class CurrencyMappingItemInput < Types::BaseInputObject
      argument :currency_code, Types::CurrencyEnum, required: true
      argument :currency_external_code, String, required: true
    end
  end
end
