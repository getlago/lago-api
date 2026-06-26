# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module IntegrationMappings
    class MappableTypeEnum < Types::BaseEnum
      ::IntegrationMappings::BaseMapping::MAPPABLE_TYPES.each do |type|
        value type
      end
    end
  end
end
