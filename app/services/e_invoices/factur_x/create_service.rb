# frozen_string_literal: true

module EInvoices
  module FacturX
    class CreateService < ::BaseService
      def initialize(invoice:)
        @invoice = invoice
      end

      def call
        File.write(
          filename,
          Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
            Create::Builder.call(xml:, invoice:)
          end.to_xml
        )
      end

      private

      attr_accessor :invoice

      def filename
        @filename ||= "output.xml"
      end
    end
  end
end
