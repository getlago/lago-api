# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Integrations
    class IntegrationTypeEnum < Types::BaseEnum
      Organization::INTEGRATIONS.each do |type|
        value type
      end
    end
  end
end
