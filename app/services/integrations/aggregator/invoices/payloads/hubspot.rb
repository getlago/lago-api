# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Payloads
        class Hubspot < BasePayload
          def create_body
            {
              'objectType' => 'LagoInvoices',
              'input' => {
                'associations' => [],
                'properties' => {
                  'lago_invoice_id' => invoice.id,
                  'lago_invoice_number' => invoice.number,
                  'lago_invoice_issuing_date' => formatted_date(invoice.issuing_date),
                  'lago_invoice_payment_due_date' => formatted_date(invoice.payment_due_date),
                  'lago_invoice_payment_overdue' => invoice.payment_overdue,
                  'lago_invoice_type' => invoice.invoice_type,
                  'lago_invoice_status' => invoice.status,
                  'lago_invoice_payment_status' => invoice.payment_status,
                  'lago_invoice_currency' => invoice.currency,
                  'lago_invoice_total_amount' => total_amount,
                  'lago_invoice_subtotal_excluding_taxes' => subtotal_excluding_taxes,
                  'lago_invoice_file_url' => invoice.file_url
                }
              }
            }
          end

          def update_body
            {
              'objectId' => integration_invoice.external_id,
              'objectType' => 'LagoInvoices',
              'input' => {
                'properties' => {
                  'lago_invoice_id' => invoice.id,
                  'lago_invoice_number' => invoice.number,
                  'lago_invoice_issuing_date' => formatted_date(invoice.issuing_date),
                  'lago_invoice_payment_due_date' => formatted_date(invoice.payment_due_date),
                  'lago_invoice_payment_overdue' => invoice.payment_overdue,
                  'lago_invoice_type' => invoice.invoice_type,
                  'lago_invoice_status' => invoice.status,
                  'lago_invoice_payment_status' => invoice.payment_status,
                  'lago_invoice_currency' => invoice.currency,
                  'lago_invoice_total_amount' => total_amount,
                  'lago_invoice_subtotal_excluding_taxes' => subtotal_excluding_taxes,
                  'lago_invoice_file_url' => invoice.file_url
                }
              }
            }
          end

          def customer_association_body
            {
              'objectType' => integration.invoices_object_type_id,
              'objectId' => integration_invoice.external_id,
              'toObjectType' => object_type,
              'toObjectId' => integration_customer.external_customer_id,
              'input' => []
            }
          end

          private

          def formatted_date(date)
            date.strftime('%Y-%m-%d')
          end

          def integration_invoice
            @integration_invoice ||= IntegrationResource.find_by(integration:, syncable: invoice)
          end

          def object_type
            if integration_customer.targeted_object == 'contacts'
              'contact'
            else
              'company'
            end
          end

          def total_amount
            amount(invoice.total_amount_cents, resource: invoice)
          end

          def subtotal_excluding_taxes
            amount(invoice.sub_total_including_taxes_amount_cents, resource: invoice)
          end
        end
      end
    end
  end
end
