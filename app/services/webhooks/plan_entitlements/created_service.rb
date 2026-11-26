# frozen_string_literal: true

module Webhooks
  module PlanEntitlements
    class CreatedService < Webhooks::BaseService
      include PlanEntitlementPayload

      private

      def webhook_type
        "plan_entitlement.created"
      end
    end
  end
end
