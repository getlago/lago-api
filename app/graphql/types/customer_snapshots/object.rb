# frozen_string_literal: true

module Types
  module CustomerSnapshots
    class Object < Types::BaseObject
      graphql_name "CustomerSnapshot"

      field :address_line1, String, null: true
      field :address_line2, String, null: true
      field :applicable_timezone, String, null: true
      field :city, String, null: true
      field :country, String, null: true
      field :display_name, String, null: true
      field :email, String, null: true
      field :firstname, String, null: true
      field :lastname, String, null: true
      field :legal_name, String, null: true
      field :legal_number, String, null: true
      field :phone, String, null: true
      field :state, String, null: true
      field :tax_identification_number, String, null: true
      field :url, String, null: true
      field :zipcode, String, null: true

      field :shipping_address, Types::Customers::Address, null: true

      def shipping_address
        return nil unless object.shipping_address_line1 || object.shipping_city || object.shipping_country

        object.shipping_address
      end
    end
  end
end
