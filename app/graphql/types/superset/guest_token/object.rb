# frozen_string_literal: true

module Types
  module Superset
    module GuestToken
      class Object < Types::BaseObject
        graphql_name "SupersetGuestToken"

        field :guest_token, String, null: false
      end
    end
  end
end
