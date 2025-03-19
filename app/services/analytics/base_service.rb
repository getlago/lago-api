# frozen_string_literal: true

module Analytics
  class BaseService < BaseService
    def initialize(organization, **filters)
      @organization = organization
      # should billing_entity_id be passed as a parameter or a filter?
      # @billing_entity = BillingEntity.find_by(organization_id: organization.id, code: billing_entity_code)
      @filters = filters

      super()
    end

    private

    attr_reader :billing_entity, :organization, :filters, :records
  end
end
