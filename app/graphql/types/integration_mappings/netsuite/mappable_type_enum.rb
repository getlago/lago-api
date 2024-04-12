# frozen_string_literal: true

module Types
  module IntegrationMappings
    module Netsuite
      class MappableTypeEnum < Types::BaseEnum
        graphql_name 'NetsuiteMappableTypeEnum'

        ::IntegrationMappings::NetsuiteMapping::MAPPABLE_TYPES.each do |type|
          value type
        end
      end
    end
  end
end
