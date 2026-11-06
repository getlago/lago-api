# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      class UpdateService < BaseService
        def initialize(integration:, integration_customer:)
          @integration_customer = integration_customer

          super(integration:)
        end

        def action_name
          case provider
          when "netsuite"
            "netsuite-update-contact"
          when "xero"
            "xero-update-contact"
          when "hubspot"
            "update-contact"
          when "avalara"
            "update-customer"
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

          result
        rescue LagoHttpClient::HttpError => e
          raise RequestLimitError.new(e) if request_limit_error?(e)

          code = code(e)
          message = message(e)

          deliver_error_webhook(customer:, code:, message:)

          result.service_failure!(code:, message:)
        end

        delegate :customer, to: :integration_customer

        private

        attr_reader :integration_customer, :subsidiary_id

        def params
          Integrations::Aggregator::Contacts::Payloads::Factory.new_instance(
            integration:,
            integration_customer:,
            customer:,
            subsidiary_id:
          ).update_body
        end
      end
    end
  end
end
