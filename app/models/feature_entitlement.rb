# frozen_string_literal: true

class FeatureEntitlement < ApplicationRecord
  belongs_to :organization
  belongs_to :feature
  belongs_to :plan, optional: true
  has_many :values, class_name: "FeatureEntitlementValue", dependent: :destroy

  # belongs_to :subscription, optional: true
  #
  # validates :plan_id, presence: true, if: -> { subscription_id.blank? }
  # validates :subscription_id, presence: true, if: -> { plan_id.blank? }
  # validates :plan_id, absence: true, if: -> { subscription_id.present? }
  # validates :subscription_id, absence: true, if: -> { plan_id.present? }
  # validates :feature_id, uniqueness: { scope: [:plan_id, :deleted_at] }, if: -> { plan_id.present? }
  # validates :feature_id, uniqueness: { scope: [:subscription_id, :deleted_at] }, if: -> { subscription_id.present? }
  # validates :organization_id, presence: true
  #
  # # Ensure entitlement belongs to same organization as feature and plan/subscription
  # validate :organization_matches_feature
  # validate :organization_matches_parent
  #
  # default_scope { where(deleted_at: nil) }
  #
  # scope :for_organization, ->(organization) { where(organization: organization) }
  # scope :for_plan, ->(plan) { where(plan: plan, subscription_external_id: nil) }
  # scope :for_subscription, ->(subscription) { where(subscription: subscription, plan: nil) }
  # scope :with_deleted, -> { unscoped }
  # scope :only_deleted, -> { unscoped.where.not(deleted_at: nil) }
  #
  # def parent
  #   plan || subscription
  # end
  #
  # def plan_entitlement?
  #   plan_id.present?
  # end
  #
  # def subscription_entitlement?
  #   subscription_id.present?
  # end
  #
  # private
  #
  # def organization_matches_feature
  #   return unless feature && organization
  #
  #   errors.add(:organization, "must match feature's organization") if feature.organization != organization
  # end
  #
  # def organization_matches_parent
  #   return unless organization && parent
  #
  #   errors.add(:organization, "must match #{parent.class.name.downcase}'s organization") if parent.organization != organization
  # end
end

# == Schema Information
#
# Table name: feature_entitlements
#
#  id                       :uuid             not null, primary key
#  deleted_at               :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  feature_id               :uuid             not null
#  organization_id          :uuid             not null
#  plan_id                  :uuid
#  subscription_external_id :string
#
# Indexes
#
#  idx_on_subscription_external_id_feature_id_46b2a138fe   (subscription_external_id,feature_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_feature_entitlements_on_feature_id                (feature_id)
#  index_feature_entitlements_on_organization_id           (organization_id)
#  index_feature_entitlements_on_plan_id                   (plan_id)
#  index_feature_entitlements_on_plan_id_and_feature_id    (plan_id,feature_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_feature_entitlements_on_subscription_external_id  (subscription_external_id)
#
# Foreign Keys
#
#  fk_rails_...  (feature_id => features.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#
