# frozen_string_literal: true

module BillingEntities
  class CreateService < BaseService
    Result = BaseResult[:billing_entity]

    def initialize(organization:, params:)
      @organization = organization
      @params = params
      super
    end

    def call
      return result.forbidden_failure! unless organization.can_create_billing_entity?

      billing_entity = organization.billing_entities.create!(
        name: params[:name],
        code: params[:code]
      )

      result.billing_entity = billing_entity
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
