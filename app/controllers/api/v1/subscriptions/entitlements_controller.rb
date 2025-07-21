# frozen_string_literal: true

module Api
  module V1
    module Subscriptions
      class EntitlementsController < Api::BaseController
        include PremiumFeatureOnly

        # TODO: Share this with SubscriptionController and AlertsController
        before_action :find_subscription

        def index
          render(
            json: ::V1::Entitlement::SubscriptionEntitlementsCollectionSerializer.new(
              Entitlement::SubscriptionEntitlement.for_subscription(subscription),
              nil,
              collection_name: "entitlements"
            ).serialize
          )
        end

        def update
          result = ::Entitlement::SubscriptionEntitlementsUpdateService.call(
            organization: current_organization,
            subscription: subscription,
            entitlements_params: update_params,
            partial: true
          )

          if result.success?
            render(
              json: ::V1::Entitlement::SubscriptionEntitlementsCollectionSerializer.new(
                Entitlement::SubscriptionEntitlement.for_subscription(subscription),
                nil,
                collection_name: "entitlements"
              ).serialize
            )
          else
            render_error_response(result)
          end
        end

        def destroy
          result = ::Entitlement::SubscriptionEntitlementDestroyService.call(subscription:, code: params[:code])

          if result.success?
            render(
              json: ::V1::Entitlement::SubscriptionEntitlementsCollectionSerializer.new(
                Entitlement::SubscriptionEntitlement.for_subscription(subscription),
                nil,
                collection_name: "entitlements"
              ).serialize
            )
          else
            render_error_response(result)
          end
        end

        def remove
          feature = current_organization.features.find_by(code: params[:code])

          result = ::Entitlement::SubscriptionFeatureRemovalCreateService.call(subscription:, feature:)

          if result.success?
            render(
              json: ::V1::Entitlement::SubscriptionEntitlementsCollectionSerializer.new(
                Entitlement::SubscriptionEntitlement.for_subscription(subscription),
                nil,
                collection_name: "entitlements"
              ).serialize
            )
          else
            render_error_response(result)
          end
        end

        def restore
          feature = current_organization.features.find_by(code: params[:code])
          return not_found_error(resource: "feature") unless feature

          result = ::Entitlement::SubscriptionFeatureRemovalDestroyService.call(subscription:, feature:)

          if result.success?
            render(
              json: ::V1::Entitlement::SubscriptionEntitlementsCollectionSerializer.new(
                Entitlement::SubscriptionEntitlement.for_subscription(subscription),
                nil,
                collection_name: "entitlements"
              ).serialize
            )
          else
            render_error_response(result)
          end
        end

        private

        attr_reader :subscription

        def update_params
          params.fetch(:entitlements, {}).permit!
        end

        def find_subscription
          @subscription = current_organization.subscriptions
            .order("terminated_at DESC NULLS FIRST, started_at DESC") # TODO: Confirm
            .find_by!(
              external_id: params[:subscription_external_id],
              status: :active # TODO: Confirm
            )
        rescue ActiveRecord::RecordNotFound
          not_found_error(resource: "subscription")
        end
      end
    end
  end
end
