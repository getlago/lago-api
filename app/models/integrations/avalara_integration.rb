# frozen_string_literal: true

module Integrations
  class AvalaraIntegration < BaseIntegration
    has_many :error_details, -> { where({error_details: {error_code: "tax_error"}}) },
      primary_key: :organization_id,
      foreign_key: :organization_id

    validates :connection_id, :account_id, :license_key, presence: true

    settings_accessors :account_id
    secrets_accessors :connection_id, :license_key
  end
end
