# frozen_string_literal: true

module Types
  module ErrorDetails
    class Object < Types::BaseObject
      graphql_name 'ErrorDetail'

      field :error_code, Types::ErrorDetails::ErrorCodesEnum, null: false
      field :error_details, String, null: true
      field :id, ID, null: false

      def error_details
        object.error_details.values&.first
      end
    end
  end
end
