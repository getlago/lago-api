# frozen_string_literal: true

module Types
  module Invoices
    class CustomerDecorator < SimpleDelegator
      extend Forwardable

      def initialize(customer, invoice)
        @invoice = invoice
        super(customer)
      end

      def_delegator :invoice, :customer_shipping_address, :shipping_address

      CustomerDataSnapshotting::SNAPSHOTTED_ATTRIBUTES.each do |attribute|
        define_method(attribute) do
          @invoice.public_send("customer_#{attribute}")
        end
      end

      private

      attr_reader :invoice
    end
  end
end
