# frozen_string_literal: true

module IntegrationCollectionMappings
  module Netsuite
    class UpdateService < BaseService
      def initialize(integration_collection_mapping:, params:)
        @integration_collection_mapping = integration_collection_mapping
        @params = params

        super
      end

      def call
        unless integration_collection_mapping
          return result.not_found_failure!(resource: 'integration_collection_mapping')
        end

        integration_collection_mapping.integration_id = params[:integration_id] if params.key?(:integration_id)
        integration_collection_mapping.mapping_type = params[:mapping_type] if params.key?(:mapping_type)
        integration_collection_mapping.netsuite_id = params[:netsuite_id] if params.key?(:netsuite_id)
        if params.key?(:netsuite_account_code)
          integration_collection_mapping.netsuite_account_code = params[:netsuite_account_code]
        end
        integration_collection_mapping.netsuite_name = params[:netsuite_name] if params.key?(:netsuite_name)

        integration_collection_mapping.save!

        result.integration_collection_mapping = integration_collection_mapping
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :integration_collection_mapping, :params
    end
  end
end
