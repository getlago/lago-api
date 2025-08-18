# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class LineItem < Builder
        def initialize(xml:, fee:, line_id:)
          @fee = fee
          @line_id = line_id

          super(xml:)
        end

        def call
          xml.comment "Line Item #{line_id}: #{line_item_description}"
          xml["cac"].InvoiceLine do
            xml["cbc"].ID line_id
            xml["cbc"].InvoicedQuantity fee.units, unitCode: UNIT_CODE
            xml["cbc"].LineExtensionAmount format_number(fee.amount), currencyID: fee.currency
            xml["cac"].Item do
              xml["cbc"].Name fee.item_name
              xml["cac"].ClassifiedTaxCategory do
                fee_category_code = tax_category_code(type: fee.fee_type, tax_rate: fee.taxes_rate)
                xml["cbc"].ID fee_category_code
                xml["cbc"].Percent fee.taxes_rate
                xml["cac"].TaxScheme do
                  xml["cbc"].ID VAT
                end
              end
              xml["cac"].AdditionalItemProperty do
                xml["cbc"].Name "Description"
                xml["cbc"].Value fee.description.presence || line_item_description
              end
            end
            xml["cac"].Price do
              xml["cbc"].PriceAmount fee.precise_unit_amount, currencyID: fee.currency
            end
          end
        end

        private

        attr_accessor :fee, :line_id
      end
    end
  end
end
