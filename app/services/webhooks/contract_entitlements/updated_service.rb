# frozen_string_literal: true

module Webhooks
  module ContractEntitlements
    class UpdatedService < Webhooks::BaseService
      include ContractEntitlementPayload

      private

      def webhook_type
        "contract_entitlement.updated"
      end
    end
  end
end
