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
            @taxable_fees ||= ordered_fees.select(&:taxable?).presence || Array(ordered_fees.first)
          end

          # NOTE: `Invoice#fees` carries no ORDER BY, so the order is pinned here: finalize and
          #       the later void refund must post the same lines in the same sequence, and the
          #       fee standing in for an untaxable invoice must be the same one on every call.
          def ordered_fees
            @ordered_fees ||= fees
              .each_with_index
              .sort_by { |fee, index| [fee.try(:created_at) || Time.zone.at(0), fee.id.to_s, index] }
              .map(&:first)
          end

          # NOTE: A charge split by charge filters or by grouped_by yields one fee per
          #       combination, so a single charge could take dozens of the 1200 line items both
          #       providers accept. Taxation is identical across the split, and equally across
          #       the subscriptions and periods one charge may be billed for on one invoice, so
          #       those collapse into the same line.
          def payload_fees
            @payload_fees ||= ChargeFeeGroup.build(taxable_fees)
          end

          def fee_groups
            @fee_groups ||= payload_fees.grep(ChargeFeeGroup).index_by(&:item_key)
          end

          def process_response(body)
            super

            result.fees = split_group_taxes(result.fees) if result.success?
          end

          def split_group_taxes(fee_taxes)
            fee_taxes.flat_map do |item|
              group = fee_groups[item.item_key] || fee_groups[item.item_id]

              group ? group.split_taxes(item) : [item]
            end
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
