# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        class BaseService < Integrations::Aggregator::Taxes::BaseService
          def initialize(invoice:, fees: nil)
            @invoice = invoice
            @fees = fees || invoice.fees

            super()
          end

          private

          attr_reader :invoice, :fees

          delegate :customer, to: :invoice, allow_nil: true

          # NOTE: A fee with no taxable base incurs no tax, so it is left out of the request to
          #       keep the payload under the provider line-item limit (Anrok and Avalara reject
          #       payloads above 1200 items). Excluded fees are absent from the response and keep
          #       their zero taxes. The invoice itself is still reported even when nothing on it
          #       is taxable, so one fee stands in for it rather than sending an empty array,
          #       which both providers reject.
          def taxable_fees
            @taxable_fees ||= fees.select(&:taxable?).presence || Array(fees.first)
          end

          # NOTE: Only an invoice carrying no fee at all reaches this, and it has nothing to
          #       report.
          def no_taxable_fees_result
            result.fees = []
            result
          end

          def process_void_response(body)
            invoice_id = body["succeededInvoices"]&.first.try(:[], "id")

            if invoice_id
              result.invoice_id = invoice_id
            else
              code, message = retrieve_error_details(body["failedInvoices"].first["validation_errors"])

              raise Integrations::Aggregator::OutOfMemoryError if message.include?(OUT_OF_MEMORY_ERROR)
              raise Integrations::Aggregator::ServerContentionError, message if server_contention_error?(message)

              deliver_tax_error_webhook(customer:, code:, message:)
              result.service_failure!(code:, message:)
            end
          end
        end
      end
    end
  end
end
