# frozen_string_literal: true

module Webhooks
  module ContractEntitlements
    class CreatedService < Webhooks::BaseService
      include ContractEntitlementPayload

      private

      def webhook_type
        "contract_entitlement.created"
      end
    end
  end
end
