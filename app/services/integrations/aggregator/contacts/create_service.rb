# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      class CreateService < BaseService
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
          end
        end

        def call
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
          raise RequestLimitError(e) if request_limit_error?(e)

          code = code(e)
          message = message(e)

          deliver_error_webhook(customer:, code:, message:)

          result.service_failure!(code:, message:)
        end

        private

        attr_reader :customer, :subsidiary_id

        def params
          Integrations::Aggregator::Contacts::Payloads::Factory.new_instance(
            integration:,
            integration_customer: nil,
            customer:,
            subsidiary_id:
          ).create_body
        end
      end
    end
  end
end
