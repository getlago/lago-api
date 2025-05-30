# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      class BaseService < Integrations::Aggregator::BaseService
        SPECIAL_TAXATION_TYPES = %w[exempt notCollecting productNotTaxed jurisNotTaxed jurisHasNoTax].freeze
        def initialize
          super(integration:)
        end

        private

        def integration
          return nil unless integration_customer

          integration_customer&.integration
        end

        def integration_customer
          @integration_customer ||= begin
            int_customers = customer.integration_customers
            int_customers.find { |ic| ic.tax_kind? }
          end
        end

        def headers
          {
            "Connection-Id" => integration.connection_id,
            "Authorization" => "Bearer #{secret_key}",
            "Provider-Config-Key" => provider_key
          }
        end

        def assign_external_customer_id
          return unless result.success?
          return if integration_customer.external_customer_id

          integration_customer.update!(external_customer_id: customer.external_id)
        end

        def process_response(body)
          fees = body["succeededInvoices"]&.first.try(:[], "fees")

          if fees
            result.fees = fees.map do |fee|
              taxes_to_pay = fee["tax_amount_cents"]

              OpenStruct.new(
                item_key: fee["item_key"],
                item_id: fee["item_id"],
                item_code: fee["item_code"],
                amount_cents: fee["amount_cents"],
                tax_amount_cents: taxes_to_pay,
                tax_breakdown: tax_breakdown(fee["tax_breakdown"], taxes_to_pay)
              )
            end
            result.succeeded_id = body["succeededInvoices"].first["id"]
          else
            code, message = retrieve_error_details(body["failedInvoices"].first["validation_errors"])

            # Temp fix for the API limit issue
            message = "API limit" if message == "Internal server error: resource contention."

            unless message.include?("API limit")
              deliver_tax_error_webhook(customer:, code:, message:) if customer.persisted? # Do not send this webhook in preview mode
            end

            result.service_failure!(code:, message:)
          end
        end

        def tax_breakdown(breakdown, taxes_to_pay)
          breakdown.map do |b|
            if SPECIAL_TAXATION_TYPES.include?(b["type"])
              OpenStruct.new(
                name: humanize_tax_name(b["reason"].presence || b["type"]),
                rate: "0.00",
                tax_amount: 0,
                type: b["type"]
              )
            elsif b["rate"]
              # If there are taxes, that client shouldn't pay, we nullify the taxes
              if taxes_to_pay.zero? && b["tax_amount"].positive?
                OpenStruct.new(
                  name: "Tax",
                  rate: "0.00",
                  tax_amount: 0,
                  type: "tax"
                )
              else
                OpenStruct.new(
                  name: b["name"],
                  rate: b["rate"],
                  tax_amount: b["tax_amount"],
                  type: b["type"]
                )
              end
            else
              OpenStruct.new(
                name: humanize_tax_name(b["reason"].presence || b["type"] || "unknown_taxation"),
                rate: "0.00",
                tax_amount: 0,
                type: b["type"] || "unknown_taxation"
              )
            end
          end
        end

        def retrieve_error_details(validation_error)
          if validation_error.is_a?(Hash)
            code = validation_error["type"]
            message = "Service failure"
            return [code, message]
          end

          code = "validationError"
          message = validation_error
          [code, message]
        end

        def humanize_tax_name(camelized_name)
          camelized_name.underscore.humanize
        end
      end
    end
  end
end
