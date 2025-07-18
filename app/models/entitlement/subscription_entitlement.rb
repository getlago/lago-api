# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlement < ApplicationRecord
    self.table_name = "entitlement_subscription_entitlements_view"

    belongs_to :organization
    belongs_to :feature, class_name: "Entitlement::Feature", foreign_key: :entitlement_feature_id
    belongs_to :privilege, class_name: "Entitlement::Privilege", foreign_key: :entitlement_privilege_id, optional: true

    scope :for_subscription, ->(sub) do
      where(organization_id: sub.organization_id, removed: false)
        .where("subscription_external_id = ? OR plan_id = ?", sub.external_id, sub.plan.parent_id || sub.plan.id)
    end

    def readonly?
      true
    end
  end
end

# == Schema Information
#
# Table name: entitlement_subscription_entitlements_view
#
#  feature_code                   :string
#  feature_deleted_at             :datetime
#  feature_description            :string
#  feature_name                   :string
#  privilege_code                 :string
#  privilege_config               :jsonb
#  privilege_deleted_at           :datetime
#  privilege_name                 :string
#  privilege_override_value       :string
#  privilege_plan_value           :string
#  privilege_value_type           :enum
#  removed                        :boolean
#  entitlement_feature_id         :uuid
#  entitlement_privilege_id       :uuid
#  organization_id                :uuid
#  override_entitlement_id        :uuid
#  override_entitlement_values_id :uuid
#  plan_entitlement_id            :uuid
#  plan_entitlement_values_id     :uuid
#  plan_id                        :uuid
#  subscription_external_id       :string
#
