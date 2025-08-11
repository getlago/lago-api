# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class PaymentTerms < Builder
        def call
          xml.comment "Payment Terms"
          xml["ram"].SpecifiedTradePaymentTerms do
            xml["ram"].Description description
            xml["ram"].DueDateDateTime do
              xml["udt"].DateTimeString formatted_date(invoice.payment_due_date), format: CCYYMMDD
            end
          end
        end

        private

        def description
          "#{I18n.t("invoice.payment_term")} #{I18n.t("invoice.payment_term_days", net_payment_term: invoice.net_payment_term)}"
        end
      end
    end
  end
end
