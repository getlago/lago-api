# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    class Object < Types::BaseObject
      graphql_name "CollectionMapping"

      field :billing_entity_id, ID, null: true
      field :id, ID, null: false
      field :integration_id, ID, null: false
      field :mapping_type, Types::IntegrationCollectionMappings::MappingTypeEnum, null: false

      field :external_account_code, String, null: true
      field :external_id, String, null: true
      field :external_name, String, null: true

      field :tax_code, String, null: true, fallback_value: nil
      field :tax_nexus, String, null: true, fallback_value: nil
      field :tax_type, String, null: true, fallback_value: nil

      field :currencies, [Types::IntegrationCollectionMappings::CurrencyMappingItem], null: true

      # Only NetSuite mappings define currencies and tax settings: other providers answer null.
      def currencies
        object.try(:currencies)&.map do |currency_code, currency_external_code|
          {currency_code:, currency_external_code:}
        end
      end
    end
  end
end
