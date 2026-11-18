# frozen_string_literal: true

module Webhooks
  module ContractEntitlements
    class DeletedService < Webhooks::BaseService
      include ContractEntitlementPayload

      private

      def webhook_type
        "contract_entitlement.deleted"
      end
    end
  end
end
