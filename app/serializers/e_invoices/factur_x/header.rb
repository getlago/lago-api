# frozen_string_literal: true

module EInvoices
  module FacturX
    class Header < BaseSerializer
      def initialize(xml:, resource:, type_code:, notes:)
        super(xml:, resource:)

        @type_code = type_code
        @notes = notes
      end

      def serialize
        xml.comment "Exchange Document Header"
        xml["rsm"].ExchangedDocument do
          xml["ram"].ID resource.number
          xml["ram"].TypeCode type_code
          xml["ram"].IssueDateTime do
            xml["udt"].DateTimeString formatted_date(resource.issuing_date), format: CCYYMMDD
          end
          notes.each do |note|
            xml["ram"].IncludedNote do
              xml["ram"].Content note
            end
          end
        end
      end

      private

      attr_accessor :type_code, :notes
    end
  end
end
