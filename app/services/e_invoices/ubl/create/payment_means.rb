# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class PaymentMeans < Builder
        def initialize(xml:, invoice:, type:, amount: nil)
          super(xml:, invoice:)

          @type = type
          @amount = amount
        end

        def call
          xml.comment "Payment Means: #{payment_label(type)}"
          xml["cac"].PaymentMeans do
            xml["cbc"].PaymentMeansCode type
          end
        end

        private

        attr_accessor :type, :amount
      end
    end
  end
end
