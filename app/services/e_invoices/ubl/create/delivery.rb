# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class Delivery < Builder
        def call
          xml.comment "Delivery Information"
          xml["cac"].Delivery do
            xml["cbc"].ActualDeliveryDate formatted_date(oldest_charges_from_datetime)
          end
        end
      end
    end
  end
end
