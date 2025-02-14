# frozen_string_literal: true

module BillingEntities
  class CreateService < BaseService
    Result = BaseResult[:billing_entity]

    def initialize(params:, organization:)
      @params = params
      @organization = organization
      super
    end

    def call
      return result.not_allowed_error(code: 'billing_entities_max_limit_reached') unless allowed_to_create_billing_entity?

      billing_entity = organization.billing_entities.new(
        params.slice(:name, :code, :document_numbering)
      )

      ActiveRecord::Base.transaction do
        billing_entity.save!
      end

      result.billing_entity = billing_entity
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :params, :organization

    def allowed_to_create_billing_entity?
      # TODO: check license here!
      return true
    end
  end
end
