# frozen_string_literal: true

module Customers
  class DestroyService < BaseService
    def initialize(customer:)
      @customer = customer

      super
    end

    def call
      return result.not_found_failure!(resource: 'customer') unless customer

      customer.discard!
      track_customer_deleted

      Customers::TerminateRelationsJob.perform_later(customer_id: customer.id)

      result.customer = customer
      result
    end

    private

    attr_reader :customer

    def track_customer_deleted
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'customer_deleted',
        properties: {
          customer_id: customer.id,
          organization_id: customer.organization_id,
          deleted_at: customer.deleted_at
        }
      )
    end
  end
end
