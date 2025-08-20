# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlement < ApplicationRecord
    self.table_name = "entitlement_subscription_entitlements_view"

    belongs_to :organization
    belongs_to :feature, class_name: "Entitlement::Feature", foreign_key: :entitlement_feature_id
    belongs_to :privilege, class_name: "Entitlement::Privilege", foreign_key: :entitlement_privilege_id, optional: true

    def self.for_subscription(sub)
      # TODO: Add entitlement_privilege_id too to remove privilege from subscription
      removed_feature_ids = SubscriptionFeatureRemoval.where(subscription_id: sub.id).pluck(:entitlement_feature_id)

      scope = where(organization_id: sub.organization_id)
        .where("subscription_id = ? OR plan_id = ?", sub.id, sub.plan.parent_id || sub.plan.id)
        .select("DISTINCT ON(plan_entitlement_id, plan_entitlement_values_id) *")
        .order(Arel.sql("plan_entitlement_id, plan_entitlement_values_id, override_entitlement_values_id IS NOT NULL DESC"))

      unless removed_feature_ids.empty?
        scope = scope.where("entitlement_feature_id NOT IN (?)", removed_feature_ids)
      end

      scope
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
#  entitlement_created_at         :datetime
#  feature_code                   :string
#  feature_created_at             :datetime
#  feature_deleted_at             :datetime
#  feature_description            :string
#  feature_name                   :string
#  privilege_code                 :string
#  privilege_config               :jsonb
#  privilege_created_at           :datetime
#  privilege_deleted_at           :datetime
#  privilege_name                 :string
#  privilege_override_value       :string
#  privilege_plan_value           :string
#  privilege_value_created_at     :datetime
#  privilege_value_type           :enum
#  entitlement_feature_id         :uuid
#  entitlement_privilege_id       :uuid
#  organization_id                :uuid
#  override_entitlement_id        :uuid
#  override_entitlement_values_id :uuid
#  plan_entitlement_id            :uuid
#  plan_entitlement_values_id     :uuid
#  plan_id                        :uuid
#  subscription_id                :uuid
#
