# frozen_string_literal: true

module EInvoice
  module FacturX
    class HeaderBuilder
      def initialize(xml, invoice:)
        @xml = xml
        @invoice = invoice
      end

      def call
        xml.comment "Exchange Document Header"
        xml['rsm'].ExchangedDocument do
          xml['ram'].ID invoice.number
          xml['ram'].TypeCode 380
          xml['ram'].IssueDateTime do
            xml['udt'].DateTimeString(invoice.issuing_date.strftime('%Y%m%d'), 'format' => 102)
          end
          xml['ram'].IncludedNote do
            xml['ram'].Content "Invoice ID: #{invoice.id}"
          end
        end
      end
 
      private

      attr_accessor :xml, :invoice
    end
  end
end
