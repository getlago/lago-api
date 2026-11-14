# frozen_string_literal: true

module V1
  module Entitlement
    # The effective entitlements of a contract, in the v1 subscription entitlement shape until
    # their v2 shape ships.
    class ContractEntitlementSerializer < SubscriptionEntitlementSerializer
    end
  end
end
