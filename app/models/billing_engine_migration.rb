# frozen_string_literal: true

class BillingEngineMigration < ApplicationRecord
  STATUSES = {shadowing: "shadowing", paused: "paused", aborted: "aborted"}.freeze
  NATIVE_V2_CONTROLLER_PREFIX = "api/v2/"

  belongs_to :organization
  belongs_to :shadow_organization, class_name: "Organization"

  enum :status, STATUSES, validate: true

  validate :shadow_organization_differs_from_organization
  validate :plan_mapping_is_valid
  validate :organizations_not_in_another_migration
  validate :v2_read_endpoints_are_native, if: :v2_read_endpoints_changed?

  after_commit :expire_lookup
  after_rollback :expire_lookup

  def self.v2_endpoint(controller_path)
    controller_path.delete_prefix(NATIVE_V2_CONTROLLER_PREFIX) if controller_path&.start_with?(NATIVE_V2_CONTROLLER_PREFIX)
  end

  def self.native_v2_endpoints
    Rails.application.routes.routes.filter_map { v2_endpoint(it.defaults[:controller]) }.uniq
  end

  def shadow_organization_isolated?
    !WebhookEndpoint.exists?(organization_id: shadow_organization_id) &&
      shadow_billing_entities_sending_outbound.none? &&
      !shadow_customers_with_dunning_campaign.exists?
  end

  private

  def expire_lookup
    BillingEngineMigrations::Lookup.expire!
  end

  def shadow_billing_entities_sending_outbound
    entities = BillingEntity.where(organization_id: shadow_organization_id)
    entities.where("cardinality(email_settings) > 0").or(entities.where.not(applied_dunning_campaign_id: nil))
  end

  def shadow_customers_with_dunning_campaign
    Customer.where(applied_dunning_campaign_id: DunningCampaign.where(organization_id: shadow_organization_id).select(:id))
  end

  def shadow_organization_differs_from_organization
    errors.add(:shadow_organization, :invalid) if shadow_organization.present? && shadow_organization == organization
  end

  def organizations_not_in_another_migration
    other_migrations = BillingEngineMigration.where.not(id:)
    errors.add(:organization, :value_already_exist) if other_migrations.exists?(shadow_organization_id: organization_id)
    errors.add(:shadow_organization, :value_already_exist) if other_migrations.exists?(organization_id: shadow_organization_id)
  end

  def v2_read_endpoints_are_native
    errors.add(:v2_read_endpoints, :invalid) unless v2_read_endpoints.is_a?(Array) && (v2_read_endpoints - self.class.native_v2_endpoints).empty?
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
#  v2_read_endpoints      :string           default([]), not null, is an Array
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
