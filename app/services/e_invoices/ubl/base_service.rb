# frozen_string_literal: true

module EInvoices
  module Ubl
    class BaseService < EInvoices::BaseService
      ROOT_NAMESPACES = {
        "xmlns" => "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
        "xmlns:cac" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
        "xmlns:cbc" => "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
      }.freeze

      DATEFORMAT = "%Y-%m-%d"

      def initialize(xml:, resource: nil)
        @xml = xml
        @resource = resource
      end

      private

      attr_accessor :xml, :resource
    end
  end
end
