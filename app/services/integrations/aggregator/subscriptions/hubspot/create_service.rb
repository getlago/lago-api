# frozen_string_literal: true

module Integrations
  module Aggregator
    module Subscriptions
      module Hubspot
        class CreateService < BaseService
          Result = BaseResult[:subscription_id, :external_id]

          def action_name
            "create-record"
          end

          def call
            return result unless integration
            return result unless integration.sync_subscriptions

            throttle!(:hubspot)

            Integrations::Hubspot::Subscriptions::DeployPropertiesService.call(integration:)

            response = trigger_action(payload.create_body)
            body = JSON.parse(response.body)

            result.external_id = body["id"]
            return result unless result.external_id

            IntegrationResource.create!(
              organization_id: integration.organization_id,
              integration:,
              external_id: result.external_id,
              syncable_id: subscription.id,
              syncable_type: "Subscription",
              resource_type: :subscription
            )

            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError(e) if request_limit_error?(e)

            code = code(e)
            message = message(e)

            deliver_error_webhook(customer:, code:, message:)

            result
          end

          def call_async
            return result.not_found_failure!(resource: "subscription") unless subscription

            ::Integrations::Aggregator::Subscriptions::Hubspot::CreateJob.perform_later(subscription:)

            result.subscription_id = subscription.id
            result
          end
        end
      end
    end
  end
end
