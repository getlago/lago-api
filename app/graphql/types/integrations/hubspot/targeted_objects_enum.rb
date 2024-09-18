# frozen_string_literal: true

module Types
  module Integrations
    class Hubspot
      class TargetedObjectsEnum < Types::BaseEnum
        ::Integrations::HubspotIntegration::TARGETED_OBJECTS.each do |type|
          value type
        end
      end
    end
  end
end
