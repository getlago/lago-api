# frozen_string_literal: true

module Types
  module ErrorDetails
    class Object < Types::BaseObject
      graphql_name 'ErrorDetail'

      field :id, ID, null: false
      field :error_code, Types::ErrorDetails::ErrorCodesEnum, null: false
      field :error_details, Types::ErrorDetails::ErrorCodesEnum, null: false
    end
  end
end
