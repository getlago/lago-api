# frozen_string_literal: true

module Integrations
  class AnrokIntegration < BaseIntegration
    validates :connection_id, :api_key, presence: true

    secrets_accessors :connection_id, :api_key
  end
end
