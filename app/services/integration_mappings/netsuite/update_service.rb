# frozen_string_literal: true

module IntegrationMappings
  module Netsuite
    class UpdateService < BaseService
      def initialize(integration_mapping:, params:)
        @integration_mapping = integration_mapping
        @params = params

        super
      end

      def call
        return result.not_found_failure!(resource: 'integration_mapping') unless integration_mapping

        integration_mapping.integration_id = params[:integration_id] if params.key?(:integration_id)
        integration_mapping.mappable_id = params[:mappable_id] if params.key?(:mappable_id)
        integration_mapping.mappable_type = params[:mappable_type] if params.key?(:mappable_type)
        integration_mapping.netsuite_id = params[:netsuite_id] if params.key?(:netsuite_id)
        if params.key?(:netsuite_account_code)
          integration_mapping.netsuite_account_code = params[:netsuite_account_code]
        end
        integration_mapping.netsuite_name = params[:netsuite_name] if params.key?(:netsuite_name)

        integration_mapping.save!

        result.integration_mapping = integration_mapping
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :integration_mapping, :params
    end
  end
end
