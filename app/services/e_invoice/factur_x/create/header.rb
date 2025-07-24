# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class Header < Builder
        def call
          xml.comment "Exchange Document Header"
          xml["rsm"].ExchangedDocument do
            xml["ram"].ID invoice.number
            xml["ram"].TypeCode 380
            xml["ram"].IssueDateTime do
              xml["udt"].DateTimeString formatted_date(invoice.issuing_date), "format" => 102
            end
            xml["ram"].IncludedNote do
              xml["ram"].Content "Invoice ID: #{invoice.id}"
            end
          end
        end
      end
    end
  end
end
