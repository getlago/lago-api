# frozen_string_literal: true

module Types
  module Customers
    class ShippingAddress < Types::BaseObject
      graphql_name 'CustomerShippingAddress'

      implements Types::Customers::Address
    end
  end
end
