# frozen_string_literal: true

module EInvoices
  module FacturX
    class InvoiceReference < BaseService
      def initialize(xml:, invoice_reference:)
        super(xml:)

        @invoice_reference = invoice_reference
      end

      def call
        xml.comment "Invoice reference"
        xml["ram"].InvoiceReferencedDocument do
          xml["ram"].IssuerAssignedID invoice_reference
        end
      end

      private

      attr_accessor :invoice_reference
    end
  end
end
