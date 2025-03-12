# frozen_string_literal: true

module BillingEntities
  class ResolveService < BaseService
    Result = BaseResult[:billing_entity]

    def initialize(organization:, billing_entity_code: nil)
      @billing_entity_code = billing_entity_code
      @active_billing_entities = organization.billing_entities.active

      super
    end

    def call
      return find_by_code if billing_entity_code.present?
      return find_unique_active_entity if active_billing_entities.one?

      result.not_found_failure!(resource: 'billing_entity')
    end

    private

    attr_reader :billing_entity_code, :active_billing_entities

    def find_by_code
      billing_entity = active_billing_entities.find_by(code: billing_entity_code)
  
      return result.not_found_failure!(resource: 'billing_entity') unless billing_entity

      result.billing_entity = billing_entity
      result
    end

    def find_unique_active_entity
      result.billing_entity = active_billing_entities.first
      result
    end
  end
end
