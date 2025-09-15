# frozen_string_literal: true

module EInvoices
  module Ubl
    class Header < BaseService
      def initialize(xml:, resource:, type_code:)
        super(xml:, resource:)

        @type_code = type_code
      end

      def call
        xml.comment "Invoice Header Information"
        xml["cbc"].ID resource.number
        xml["cbc"].IssueDate formatted_date(resource.issuing_date)
        xml["cbc"].InvoiceTypeCode type_code
        xml["cbc"].DocumentCurrencyCode resource.currency
      end

      private

      attr_accessor :type_code
    end
  end
end
