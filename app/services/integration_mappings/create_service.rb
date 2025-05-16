# frozen_string_literal: true

module IntegrationMappings
  class CreateService < BaseService
    def call(**args)
      integration = Integrations::BaseIntegration.find_by(id: args[:integration_id])

      return result.not_found_failure!(resource: "integration") unless integration

      integration_mapping = IntegrationMappings::Factory.new_instance(integration:).new(
        organization_id: integration.organization_id,
        integration_id: args[:integration_id],
        mappable_id: args[:mappable_id],
        mappable_type: args[:mappable_type]
      )

      integration_mapping.external_id = args[:external_id] if args.key?(:external_id)
      integration_mapping.external_account_code = args[:external_account_code] if args.key?(:external_account_code)
      integration_mapping.external_name = args[:external_name] if args.key?(:external_name)

      integration_mapping.save!

      result.integration_mapping = integration_mapping
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
