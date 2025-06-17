# frozen_string_literal: true

module IntegrationCollectionMappings
  class CreateService < BaseService
    attr_reader :params

    def initialize(params:)
      @params = params

      super
    end

    def call
      integration = Integrations::BaseIntegration.find_by(id: params[:integration_id])

      return result.not_found_failure!(resource: "integration") unless integration

      integration_collection_mapping = IntegrationCollectionMappings::Factory.new_instance(integration:).new(
        organization_id: params[:organization_id],
        integration_id: params[:integration_id],
        mapping_type: params[:mapping_type]
      )

      integration_collection_mapping.organization = integration.organization
      integration_collection_mapping.external_id = params[:external_id] if params.key?(:external_id)
      if params.key?(:external_account_code)
        integration_collection_mapping.external_account_code = params[:external_account_code]
      end
      integration_collection_mapping.external_name = params[:external_name] if params.key?(:external_name)
      integration_collection_mapping.tax_nexus = params[:tax_nexus] if params.key?(:tax_nexus)
      integration_collection_mapping.tax_code = params[:tax_code] if params.key?(:tax_code)
      integration_collection_mapping.tax_type = params[:tax_type] if params.key?(:tax_type)

      integration_collection_mapping.save!

      result.integration_collection_mapping = integration_collection_mapping
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
