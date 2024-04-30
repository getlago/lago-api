# frozen_string_literal: true

module Types
  module IntegrationMappings
    class MappableTypeEnum < Types::BaseEnum
      graphql_name 'MappableTypeEnum'

      ::IntegrationMappings::BaseMapping::MAPPABLE_TYPES.each do |type|
        value type
      end
    end
  end
end
