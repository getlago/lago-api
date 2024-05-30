# frozen_string_literal: true

module Integrations
  class AnrokIntegration < BaseIntegration
    validates :api_key, presence: true

    secrets_accessors :api_key
  end
end
