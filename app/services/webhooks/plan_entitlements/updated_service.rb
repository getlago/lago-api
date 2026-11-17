# frozen_string_literal: true

module Webhooks
  module PlanEntitlements
    class UpdatedService < Webhooks::BaseService
      include PlanEntitlementPayload

      private

      def webhook_type
        "plan_entitlement.updated"
      end
    end
  end
end
