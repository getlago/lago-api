# frozen_string_literal: true

module Types
  module Customers
    class SingleObject < Types::Customers::Object
      graphql_name 'CustomerDetails'

      field :invoices, [Types::Invoices::Object]
    end
  end
end
