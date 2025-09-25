# frozen_string_literal: true

module Types
  module Invoices
    class CustomerDecorator < SimpleDelegator
      SNAPSHOTTED_CUSTOMER_ATTRIBUTES = %i[
        display_name
        firstname
        lastname
        email
        phone
        url
        tax_identification_number
        applicable_timezone
        timezone
        address_line1
        address_line2
        city
        state
        zipcode
        country
        legal_name
        legal_number
      ].freeze

      def initialize(customer, invoice)
        @invoice = invoice
        super(customer)
      end

      SNAPSHOTTED_CUSTOMER_ATTRIBUTES.each do |attribute|
        define_method(attribute) do
          invoice.send("customer_#{attribute}")
        end
      end

      private

      attr_reader :invoice
    end
  end
end
