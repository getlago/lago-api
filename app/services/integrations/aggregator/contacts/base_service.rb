# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      class BaseService < Integrations::Aggregator::BaseService
        Result = BaseResult[:contact_id, :email]

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

        def trigger_quickbooks_action(body)
          throttle!(:quickbooks)
          process_quickbooks_result(JSON.parse(trigger_action(body).body))
        end

        # A QuickBooks rate limit waits for the next window instead of failing the job.
        def raise_if_quickbooks_rate_limited!(http_error)
          raise throttling_error(:quickbooks) if provider == "quickbooks" && quickbooks_rate_limited?(http_error)
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
