# frozen_string_literal: true

module Integrations
  class AnrokIntegration < BaseIntegration
    has_many :error_details, -> { where({error_details: {error_code: 'tax_error'}}) },
             primary_key: :organization_id,
             foreign_key: :organization_id

    validates :connection_id, :api_key, presence: true

    secrets_accessors :connection_id, :api_key
  end
end
