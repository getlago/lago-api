# frozen_string_literal: true

module Types
  module CustomerMetadata
    class Input < Types::BaseInputObject
      graphql_name 'CustomerMetadataInput'

      argument :id, ID, required: false
      argument :key, String, required: true
      argument :value, String, required: true

      argument :display_in_invoice, Boolean, required: true
    end
  end
end
