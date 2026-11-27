# frozen_string_literal: true

module BillingEngineMigrationsHelper
  # Updates a fresh copy, so a let_it_be organization keeps its events store for the other examples.
  def create_migration_shadowed_by(organization, **attributes)
    shadow_organization = Organization.find(organization.id)
    shadow_organization.update!(clickhouse_events_store: true)
    create(:billing_engine_migration, organization: create(:organization), shadow_organization:, **attributes)
  end
end
