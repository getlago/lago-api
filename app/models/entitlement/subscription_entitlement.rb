# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlement
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :organization_id, :string
    attribute :entitlement_feature_id, :string
    attribute :code, :string
    attribute :name, :string
    attribute :description, :string
    attribute :plan_entitlement_id, :string
    attribute :sub_entitlement_id, :string
    attribute :plan_id, :string
    attribute :subscription_id, :string
    attribute :ordering_date, :datetime

    attribute :privileges

    def self.for_subscription(subscription)
      SubscriptionEntitlementQuery.call(
        organization: subscription.organization,
        filters: {
          subscription_id: subscription.id,
          plan_id: subscription.plan.parent_id || subscription.plan.id
        }
      )
    end

    # Catalog plans have no parent, so there is no fallback as for subscriptions.
    def self.for_contract(contract)
      SubscriptionEntitlementQuery.call(
        organization: contract.organization,
        filters: {
          contract_id: contract.id,
          catalog_plan_id: contract.catalog_plan_id
        }
      )
    end

    def to_h
      h = attributes
      h["privileges"] = (h["privileges"] || []).map(&:to_h).index_by { |p| p[:code] }
      h.with_indifferent_access
    end
  end
end
