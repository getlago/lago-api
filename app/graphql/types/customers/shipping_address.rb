# frozen_string_literal: true

module Types
  module Customers
    class ShippingAddress < Types::BaseObject
      graphql_name 'CustomerShippingAddress'

      field :address_line1, String, null: true
      field :address_line2, String, null: true
      field :country, String, null: true
      field :state, String, null: true
      field :city, String, null: true
      field :zipcode, String, null: true
    end
  end
end
