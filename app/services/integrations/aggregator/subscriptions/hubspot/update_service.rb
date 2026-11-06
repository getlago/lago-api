# frozen_string_literal: true

module Integrations
  module Aggregator
    module Subscriptions
      module Hubspot
        class UpdateService < BaseService
          Result = BaseResult[:subscription_id, :external_id]

          def action_name
            "update-record"
          end

          def call
            return result unless integration
            return result unless integration.sync_subscriptions
            return result unless payload.integration_subscription

            throttle!(:hubspot)

            Integrations::Hubspot::Subscriptions::DeployPropertiesService.call(integration:)

            response = trigger_action(payload.update_body)
            body = JSON.parse(response.body)

            result.external_id = body["id"]
            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError.new(e) if request_limit_error?(e)

            code = code(e)
            message = message(e)

            deliver_error_webhook(customer:, code:, message:)

            result
          end

          def call_async
            return result.not_found_failure!(resource: "subscription") unless subscription

            ::Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)

            result.subscription_id = subscription.id
            result
          end
        end
      end
    end
  end
end
