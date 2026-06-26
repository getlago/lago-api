# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Integrations
    class Hubspot
      class TargetedObjectsEnum < Types::BaseEnum
        graphql_name "HubspotTargetedObjectsEnum"

        ::Integrations::HubspotIntegration::TARGETED_OBJECTS.each do |type|
          value type
        end
      end
    end
  end
end
