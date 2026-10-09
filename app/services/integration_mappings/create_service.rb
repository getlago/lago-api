# frozen_string_literal: true

module IntegrationMappings
  class CreateService < BaseService
    Result = BaseResult[:integration_mapping]

    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super()
    end

    def call
      integration = organization.integrations.find_by(id: params[:integration_id])

      return result.not_found_failure!(resource: "integration") unless integration

      if (billing_entity_id = params[:billing_entity_id])
        billing_entity = organization.billing_entities.find_by(id: billing_entity_id)
        return result.not_found_failure!(resource: "billing_entity") unless billing_entity
      end

      mappable_attributes = {
        mappable_id: params[:mappable_id],
        mappable_type: params[:mappable_type]
      }

      if params[:mappable_type] == "Product"
        product = organization.products.find_by(id: params[:mappable_id])
        return result.not_found_failure!(resource: "product") unless product

        mappable_attributes = {mappable: product}
      end

      integration_mapping = IntegrationMappings::Factory.new_instance(integration:).new(
        organization:,
        integration:,
        billing_entity:,
        **mappable_attributes
      )

      integration_mapping.external_id = params[:external_id] if params.key?(:external_id)
      integration_mapping.external_account_code = params[:external_account_code] if params.key?(:external_account_code)
      integration_mapping.external_name = params[:external_name] if params.key?(:external_name)

      integration_mapping.save!

      result.integration_mapping = integration_mapping
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
