# frozen_string_literal: true

module EntitlementHelper
  # Inserts features in bulk: hundreds of factory calls would make the limit examples slow.
  # Returns {code => id}.
  def bulk_create_features(organization, count)
    return {} if count.zero?

    now = Time.current
    rows = Array.new(count) { {organization_id: organization.id, code: "bulk_#{it}", name: "Bulk #{it}", created_at: now, updated_at: now} }
    Entitlement::Feature.insert_all!(rows, returning: %w[code id]).rows.to_h # rubocop:disable Rails/SkipsModelValidations
  end
end
