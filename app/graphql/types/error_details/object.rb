# frozen_string_literal: true

module Types
  module ErrorDetails
    class Object < Types::BaseObject
      graphql_name 'ErrorDetail'

      field :error_code, Types::ErrorDetails::ErrorCodesEnum, null: false
      field :error_details, GraphQL::Types::JSON, null: true
      field :id, ID, null: false
    end
  end
end
