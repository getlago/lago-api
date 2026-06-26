# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Integrations
    class PremiumIntegrationTypeEnum < Types::BaseEnum
      Organization::PREMIUM_INTEGRATIONS.each do |type|
        value type
      end
    end
  end
end
