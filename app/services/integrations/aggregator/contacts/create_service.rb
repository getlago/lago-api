# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      class CreateService < BaseService
        QUICKBOOKS_DUPLICATE_NAME_ERROR_CODE = "6240"

        def initialize(integration:, customer:, subsidiary_id:)
          @customer = customer
          @subsidiary_id = subsidiary_id

          super(integration:)
        end

        def action_name
          case provider
          when "netsuite"
            "netsuite-create-contact"
          when "xero"
            "xero-create-contact"
          when "hubspot"
            "create-contact"
          when "avalara"
            "create-customer"
          when "quickbooks"
            "create-customer"
          end
        end

        def call
          return create_in_quickbooks if provider == "quickbooks"

          Integrations::Hubspot::Contacts::DeployPropertiesService.call(integration:)

          throttle!(:anrok, :hubspot, :netsuite, :xero)

          response = trigger_action(params)
          body = JSON.parse(response.body)

          if body.is_a?(Hash)
            process_hash_result(body)
          else
            process_string_result(body)
          end

          return result unless result.contact_id

          deliver_success_webhook(customer:, webhook_code:)

          result
        rescue LagoHttpClient::HttpError => e
          raise RequestLimitError.new(e) if request_limit_error?(e)
          raise_if_quickbooks_rate_limited!(e)

          code = code(e)
          message = message(e)

          deliver_error_webhook(customer:, code:, message:)

          result.service_failure!(code:, message:)
        end

        private

        attr_reader :customer, :subsidiary_id

        def params
          payload.create_body
        end

        def payload
          @payload ||= Integrations::Aggregator::Contacts::Payloads::Factory.new_instance(
            integration:,
            integration_customer: nil,
            customer:,
            subsidiary_id:
          )
        end

        def create_in_quickbooks
          create_quickbooks_customer(payload.create_body)
          return result if result.failure?

          deliver_success_webhook(customer:, webhook_code:)

          result
        end

        # QuickBooks refuses a DisplayName already used by another customer, vendor or employee. When the
        # customer holding it is one Lago created in an earlier attempt that did not store its id, that id is
        # kept. Otherwise the call is made once more with the external id appended, and not retried again.
        def create_quickbooks_customer(body, retry_with_unique_name: true)
          trigger_quickbooks_action(body)
        rescue LagoHttpClient::HttpError => e
          raise unless quickbooks_duplicate_name_error?(e)

          existing = Integrations::Aggregator::Contacts::FindQuickbooksCustomerService.call(
            integration:,
            display_name: body["DisplayName"],
            notes_marker: payload.notes_marker
          )
          return lookup_failed(existing.error) unless existing.success?

          if existing.contact_id
            result.contact_id = existing.contact_id
            return
          end

          unique_body = payload.with_unique_display_name(body) if retry_with_unique_name
          raise unless unique_body

          create_quickbooks_customer(unique_body, retry_with_unique_name: false)
        end

        # The Nango action error shape around Intuit's fault is not documented, so the whole parsed body is searched.
        def quickbooks_duplicate_name_error?(http_error)
          intuit_error_code?(http_error.json_message, QUICKBOOKS_DUPLICATE_NAME_ERROR_CODE)
        rescue JSON::ParserError
          false
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

        def lookup_failed(error)
          deliver_error_webhook(customer:, code: error.code, message: error.error_message)
          result.service_failure!(code: error.code, message: error.error_message)
        end
      end
    end
  end
end
