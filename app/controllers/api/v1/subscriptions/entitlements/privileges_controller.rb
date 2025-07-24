# frozen_string_literal: true

module Api
  module V1
    module Subscriptions
      module Entitlements
        class PrivilegesController < Api::BaseController
          include PremiumFeatureOnly

          before_action :find_subscription

          def destroy
            result = ::Entitlement::SubscriptionEntitlementPrivilegeDestroyService.call(
              subscription:,
              feature_code: params[:entitlement_code],
              privilege_code: params[:code]
            )

            if result.success?
              render(
                json: ::V1::Entitlement::SubscriptionEntitlementsCollectionSerializer.new(
                  Entitlement::SubscriptionEntitlement.for_subscription(subscription),
                  collection_name: "entitlements"
                ).serialize
              )
            else
              render_error_response(result)
            end
          end

          private

          attr_reader :subscription

          def resource_name
            "subscription"
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
end
