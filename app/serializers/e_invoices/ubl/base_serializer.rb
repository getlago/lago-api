# frozen_string_literal: true

module EInvoices
  module Ubl
    class BaseSerializer < EInvoices::BaseSerializer
      COMMON_NAMESPACES = {
        "xmlns:cac" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
        "xmlns:cbc" => "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
      }

      INVOICE_NAMESPACES = {
        "xmlns" => "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
      }.merge(COMMON_NAMESPACES).freeze

      CREDIT_NOTE_NAMESPACES = {
        "xmlns" => "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2"
      }.merge(COMMON_NAMESPACES).freeze

      DATEFORMAT = "%Y-%m-%d"
    end
  end
end
