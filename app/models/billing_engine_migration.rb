# frozen_string_literal: true

class BillingEngineMigration < ApplicationRecord
  STATUSES = {shadowing: "shadowing", paused: "paused", aborted: "aborted"}.freeze

  belongs_to :organization
  belongs_to :shadow_organization, class_name: "Organization"

  enum :status, STATUSES, validate: true

  validate :shadow_organization_differs_from_organization
  validate :plan_mapping_is_valid
  validate :organizations_not_in_another_migration

  def shadow_organization_isolated?
    !WebhookEndpoint.exists?(organization_id: shadow_organization_id) && shadow_billing_entities_sending_outbound.none?
  end

  private

  def shadow_billing_entities_sending_outbound
    entities = BillingEntity.where(organization_id: shadow_organization_id)
    entities.where("cardinality(email_settings) > 0").or(entities.where.not(applied_dunning_campaign_id: nil))
  end

  def shadow_organization_differs_from_organization
    errors.add(:shadow_organization, :invalid) if shadow_organization.present? && shadow_organization == organization
  end

  def organizations_not_in_another_migration
    other_migrations = BillingEngineMigration.where.not(id:)
    errors.add(:organization, :value_already_exist) if other_migrations.exists?(shadow_organization_id: organization_id)
    errors.add(:shadow_organization, :value_already_exist) if other_migrations.exists?(organization_id: shadow_organization_id)
  end

  def plan_mapping_is_valid
    errors.add(:plan_mapping, :invalid) unless valid_plan_mapping?
  end

  def valid_plan_mapping?
    plan_mapping.is_a?(Hash) && plan_mapping.all? { |code, catalog_code| present_string?(code) && present_string?(catalog_code) }
  end

  def present_string?(value)
    value.is_a?(String) && value.present?
  end
end

# == Schema Information
#
# Table name: billing_engine_migrations
# Database name: primary
#
#  id                     :uuid             not null, primary key
#  plan_mapping           :jsonb            not null
#  status                 :enum             default("shadowing"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  organization_id        :uuid             not null
#  shadow_organization_id :uuid             not null
#
# Indexes
#
#  index_billing_engine_migrations_on_organization_id         (organization_id) UNIQUE
#  index_billing_engine_migrations_on_shadow_organization_id  (shadow_organization_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (shadow_organization_id => organizations.id)
#
