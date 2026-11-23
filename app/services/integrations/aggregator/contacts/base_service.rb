# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      class BaseService < Integrations::Aggregator::BaseService
        Result = BaseResult[:contact_id, :email]

        QUICKBOOKS_DUPLICATE_NAME_ERROR_CODE = "6240"

        private

        def deliver_success_webhook(customer:, webhook_code:)
          SendWebhookJob.perform_later(
            webhook_code,
            customer
          )
        end

        def process_hash_result(body)
          contact = body["succeededContacts"]&.first
          contact_id = contact&.dig("id")
          email = contact&.dig("email")

          if contact_id
            result.contact_id = contact_id
            result.email = email if email.present?
          else
            message = if body.key?("failedContacts")
              body["failedContacts"].first["validation_errors"].map { |error| error["Message"] }.join(". ")
            else
              body.dig("error", "payload", "message")
            end

            code = "Validation error"

            deliver_error_webhook(customer:, code:, message:)
          end
        end

        def process_string_result(body)
          result.contact_id = body
        end

        def process_quickbooks_result(body)
          contact_id = body["id"] if body.is_a?(Hash)

          if contact_id.present?
            result.contact_id = contact_id.to_s
          else
            code = "customer_id_missing"
            message = "QuickBooks returned no customer id"

            deliver_error_webhook(customer:, code:, message:)
            result.service_failure!(code:, message:)
          end
        end

        # QuickBooks refuses a DisplayName already used by another customer, vendor or employee:
        # the call is made once more with the external id appended, and a second error is not retried.
        def trigger_quickbooks_action_with_unique_name_retry(body)
          throttle!(:quickbooks)
          trigger_action(body)
        rescue LagoHttpClient::HttpError => e
          raise unless quickbooks_duplicate_name_error?(e)

          throttle!(:quickbooks)
          trigger_action(payload.with_unique_display_name(body))
        end

        # The Nango action error shape around Intuit's fault is not documented, so the whole parsed body is searched.
        def quickbooks_duplicate_name_error?(http_error)
          intuit_error_code?(http_error.json_message, QUICKBOOKS_DUPLICATE_NAME_ERROR_CODE)
        end

        def intuit_error_code?(node, error_code)
          case node
          when Hash
            node.any? do |key, value|
              (%w[code Code].include?(key) && value.to_s == error_code) || intuit_error_code?(value, error_code)
            end
          when Array
            node.any? { |value| intuit_error_code?(value, error_code) }
          else
            false
          end
        end

        def webhook_code
          case provider
          when "hubspot"
            "customer.crm_provider_created"
          else
            "customer.accounting_provider_created"
          end
        end
      end
    end
  end
end
