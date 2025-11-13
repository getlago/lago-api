# frozen_string_literal: true

module Types
  module Superset
    module Token
      class Object < Types::BaseObject
        graphql_name "Token"

        field :guest_token, String, null: false
        field :access_token, String, null: true
      end
    end
  end
end
  