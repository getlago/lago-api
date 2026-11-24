# frozen_string_literal: true

module Api
  # The key of an organization being migrated reads the native v2 endpoints its migration opens from the
  # shadow organization. Its writes are refused on every native v2 endpoint, so the two organizations never drift.
  module ShadowOrganizationReads
    extend ActiveSupport::Concern

    SERVED_FROM_HEADER = "X-Lago-Served-From"

    included do
      before_action :serve_reads_from_shadow_organization
    end

    private

    def serve_reads_from_shadow_organization
      migration = BillingEngineMigrations::Lookup.for_source(current_organization.id)
      return unless migration
      return forbidden_error(code: "organization_migration_read_only") unless read_request?
      return unless migration.serves_v2_reads?(BillingEngineMigration.v2_endpoint(controller_path))

      @current_organization = Organization.find(migration.shadow_organization_id)
      response.set_header(SERVED_FROM_HEADER, "shadow_organization")
    end

    def read_request?
      request.get? || request.head?
    end
  end
end
