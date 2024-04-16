# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    module Netsuite
      class MappingTypeEnum < Types::BaseEnum
        graphql_name 'NetsuiteMappingTypeEnum'

        ::IntegrationCollectionMappings::NetsuiteCollectionMapping::MAPPING_TYPES.each do |type|
          value type
        end
      end
    end
  end
end
