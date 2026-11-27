# frozen_string_literal: true

module Integrations
  class QuickbooksIntegration < BaseIntegration
    # Unique indexes of a QuickBooks row and the field each one guards, for `unique_index_failure!`.
    UNIQUE_INDEXES = {
      "index_integrations_on_organization_id_and_quickbooks_realm_id" => :realm_id,
      "index_integrations_on_code_and_organization_id" => :code
    }.freeze

    settings_accessors :sync_invoices, :sync_credit_notes, :sync_payments, :realm_id, :sandbox
    secrets_accessors :connection_id

    validates :connection_id, presence: true
    validate :realm_id_uniqueness

    # The setting is stored uncast: only true and "true" select the sandbox
    def sandbox?
      sandbox.to_s == "true"
    end

    private

    # Gives the friendly error before the insert. The unique index enforces it under concurrency.
    def realm_id_uniqueness
      return if realm_id.blank?

      duplicate = ::Integrations::QuickbooksIntegration
        .where(organization_id:)
        .where("settings->>'realm_id' = ?", realm_id.to_s)
        .where.not(id:)
        .exists?

      if duplicate
        errors.add(:realm_id, "value_already_exist")
      end
    end
  end
end

# == Schema Information
#
# Table name: integrations
# Database name: primary
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  name            :string           not null
#  secrets         :string
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_integrations_on_code_and_organization_id  (code,organization_id) UNIQUE
#  index_integrations_on_organization_id           (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
