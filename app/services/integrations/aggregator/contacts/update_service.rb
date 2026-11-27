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
          when "quickbooks"
            "update-customer"
          end
        end

        def call
          return update_in_quickbooks if provider == "quickbooks"

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
          raise_if_quickbooks_rate_limited!(e)

          code = code(e)
          message = message(e)

          deliver_error_webhook(customer:, code:, message:)

          result.service_failure!(code:, message:)
        end

        delegate :customer, to: :integration_customer

        private

        attr_reader :integration_customer, :subsidiary_id

        def params
          payload.update_body
        end

        def payload
          @payload ||= Integrations::Aggregator::Contacts::Payloads::Factory.new_instance(
            integration:,
            integration_customer:,
            customer:,
            subsidiary_id:
          )
        end

        # QuickBooks refuses an update without the current SyncToken, so it is read through the Nango proxy first.
        # A name already used in QuickBooks fails the update: the customer is never renamed. A customer created
        # under the suffixed name, because the name was taken, keeps it.
        def update_in_quickbooks
          token_result = Integrations::Aggregator::Contacts::FetchQuickbooksSyncTokenService.call(
            integration:,
            integration_customer:
          )

          unless token_result.success?
            code = token_result.error.code
            message = token_result.error.error_message

            deliver_error_webhook(customer:, code:, message:)

            return result.service_failure!(code:, message:)
          end

          body = payload.update_body.merge("SyncToken" => token_result.sync_token)
          if payload.unique_display_name.present? && token_result.display_name == payload.unique_display_name
            body["DisplayName"] = payload.unique_display_name
          end

          trigger_quickbooks_action(body)

          result
        end
      end
    end
  end
end
