# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class Builder < CreateService
        ROOT_NAMESPACES = {
          "xmlns" => "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
          "xmlns:cac" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
          "xmlns:cbc" => "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
        }.freeze

        DATEFORMAT = "%Y-%m-%d"

        def initialize(xml:, invoice: nil)
          @xml = xml
          @invoice = invoice
        end

        def call
          xml.Invoice(ROOT_NAMESPACES) do
            xml.comment "UBL Version and Customization"
            xml["cbc"].UBLVersionID "2.1"
            xml["cbc"].CustomizationID "urn:cen.eu:en16931:2017"

            Header.call(xml:, invoice:)
            SupplierParty.call(xml:, invoice:)
            CustomerParty.call(xml:, invoice:)
            Delivery.call(xml:, invoice:)
            credits_and_payments do |type, amount|
              PaymentMeans.call(xml:, invoice:, type:, amount:)
            end
            PaymentTerms.call(xml:, invoice:)
            allowance_charges do |tax_rate, amount|
              AllowanceCharge.call(xml:, invoice:, tax_rate:, amount:)
            end
          end
        end

        protected

        attr_accessor :xml, :invoice
      end
    end
  end
end
