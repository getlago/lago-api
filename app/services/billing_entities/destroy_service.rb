# frozen_string_literal: true

module BillingEntity
  class DestroyService < BaseService
    Result = BaseResult[:billing_entity]

    def initialize(billing_entity:)
      @billing_entity = billing_entity
      super
    end

    # Note: we don't open endpoints to use this service, but for us to correctly
    # archive an entity it makes sense to have this service
    def call
      return result.not_found_failure!(resource: 'billing_entity') unless billing_entity

      ActiveRecord::Base.transaction do
        billing_entity.discard!

        # all the logic related to discarding a billing_entity
      end

      result.billing_entity = billing_entity
      result
    end

    private

    attr_reader :billing_entity
  end
end
