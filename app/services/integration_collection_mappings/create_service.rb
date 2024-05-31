# frozen_string_literal: true

module IntegrationCollectionMappings
  class CreateService < BaseService
    def call(**args)
      integration = Integrations::BaseIntegration.find_by(id: args[:integration_id])

      return result.not_found_failure!(resource: 'integration') unless integration

      integration_collection_mapping = IntegrationCollectionMappings::Factory.new_instance(integration:).new(
        integration_id: args[:integration_id],
        mapping_type: args[:mapping_type]
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
