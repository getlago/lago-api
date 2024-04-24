# frozen_string_literal: true

module IntegrationCollectionMappings
  module Netsuite
    class CreateService < BaseService
      def call(**args)
        integration_collection_mapping = IntegrationCollectionMappings::NetsuiteCollectionMapping.new(
          integration_id: args[:integration_id],
          mapping_type: args[:mapping_type],
        )

        integration_collection_mapping.external_id = args[:external_id] if args.key?(:external_id)
        if args.key?(:external_account_code)
          integration_collection_mapping.external_account_code = args[:external_account_code]
        end
        integration_collection_mapping.external_name = args[:external_name] if args.key?(:external_name)

        integration_collection_mapping.save!

        result.integration_collection_mapping = integration_collection_mapping
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end
    end
  end
end
