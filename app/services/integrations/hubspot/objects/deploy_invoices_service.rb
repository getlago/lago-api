# frozen_string_literal: true

module Integrations
  module Hubspot
    module Objects
      class DeployInvoicesService < Integrations::Aggregator::BaseService
        VERSION = 1

        def action_path
          "v1/hubspot/object"
        end

        def call
          return unless integration.type == 'Integrations::HubspotIntegration'
          return result if integration.invoices_properties_version == VERSION
          response = nil
          ActiveRecord::Base.transaction do
            response = http_client.post_with_response(payload, headers)
            integration.invoices_properties_version = VERSION
            integration.save!
          end
          result.response = response
          result
        rescue LagoHttpClient::HttpError => e
          code = code(e)
          message = message(e)
          deliver_error_webhook(customer:, code:, message:)
          return result if e.error_code.to_i < 500
          raise e
        rescue Integrations::Aggregator::BasePayload::Failure => e
          deliver_error_webhook(customer:, code:, message:)
        end

        private

        def headers
          {
            'Provider-Config-Key' => 'hubspot',
            'Authorization' => "Bearer #{secret_key}",
            'Connection-Id' => integration.connection_id
          }
        end

        def payload
          {
            name: "LagoInvoices",
            description: "Invoices issued by Lago billing engine",
            requiredProperties: [
              "lago_invoice_id"
            ],
            labels: {
              singular: "LagoInvoice",
              plural: "LagoInvoices"
            },
            primaryDisplayProperty: "lago_invoice_number",
            secondaryDisplayProperties: %w[lago_invoice_status lago_invoice_id],
            searchableProperties: %w[lago_invoice_number lago_invoice_id],
            properties: [
              {
                name: "lago_invoice_id",
                label: "Lago Invoice Id",
                type: "string",
                fieldType: "text",
                hasUniqueValue: true,
                searchableInGlobalSearch: true
              },
              {
                name: "lago_invoice_number",
                label: "Lago Invoice Number",
                type: "string",
                fieldType: "text",
                searchableInGlobalSearch: true
              },
              {
                name: "lago_invoice_issuing_date",
                label: "Lago Invoice Issuing Date",
                type: "date",
                fieldType: "date"
              },
              {
                name: "lago_invoice_payment_due_date",
                label: "Lago Invoice Payment Due Date",
                type: "date",
                fieldType: "date"
              },
              {
                name: "lago_invoice_payment_overdue",
                label: "Lago Invoice Payment Overdue",
                groupName: "LagoInvoices",
                type: "bool",
                fieldType: "booleancheckbox",
                options: [
                  {
                    label: "True",
                    value: "true"
                  },
                  {
                    label: "False",
                    value: "false"
                  }
                ]
              },
              {
                name: "lago_invoice_type",
                label: "Lago Invoice Type",
                type: "string",
                fieldType: "text"
              },
              {
                name: "lago_invoice_status",
                label: "Lago Invoice Status",
                type: "string",
                fieldType: "text"
              },
              {
                name: "lago_invoice_payment_status",
                label: "Lago Invoice Payment Status",
                type: "string",
                fieldType: "text"
              },
              {
                name: "lago_invoice_currency",
                label: "Lago Invoice Currency",
                type: "string",
                fieldType: "text"
              },
              {
                name: "lago_invoice_total_amount",
                label: "Lago Invoice Total Amount",
                type: "number",
                fieldType: "number"
              },
              {
                name: "lago_invoice_subtotal_excluding_taxes",
                label: "Lago Invoice Subtotal Excluding Taxes",
                type: "number",
                fieldType: "number"
              },
              {
                name: "lago_invoice_file_url",
                label: "Lago Invoice File URL",
                type: "string",
                fieldType: "file"
              }
            ],
            associatedObjects: %w[COMPANY CONTACT]
          }
        end
      end
    end
  end
end
