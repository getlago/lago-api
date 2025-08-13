# frozen_string_literal: true

module EInvoices
  module Ubl
    class CreateService < EInvoices::BaseService
      def call
        return result.not_found_failure!(resource: "invoice") unless invoice

        result.xml = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          Create::Builder.call(xml:, invoice:)
        end.to_xml

        result
      end
    end
  end
end
