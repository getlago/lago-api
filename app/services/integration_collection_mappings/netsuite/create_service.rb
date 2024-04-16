# frozen_string_literal: true

module IntegrationCollectionMappings
  module Netsuite
    class CreateService < BaseService
      def call(**args)
        integration_collection_mapping = IntegrationCollectionMappings::NetsuiteCollectionMapping.new(
          integration_id: args[:integration_id],
          mapping_type: args[:mapping_type],
        )

        integration_collection_mapping.netsuite_id = args[:netsuite_id] if args.key?(:netsuite_id)
        if args.key?(:netsuite_account_code)
          integration_collection_mapping.netsuite_account_code = args[:netsuite_account_code]
        end
        integration_collection_mapping.netsuite_name = args[:netsuite_name] if args.key?(:netsuite_name)

        integration_collection_mapping.save!

        result.integration_collection_mapping = integration_collection_mapping
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end
    end
  end
end
