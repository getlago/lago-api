# frozen_string_literal: true

module BillingEntities
  class UpdateInvoiceGracePeriodService < BaseService
    Result = BaseResult[:billing_entity]

    def initialize(billing_entity:, grace_period:)
      @billing_entity = billing_entity
      @grace_period = grace_period.to_i
      super
    end

    def call
      old_grace_period = billing_entity.invoice_grace_period.to_i

      if grace_period != old_grace_period
        billing_entity.invoice_grace_period = grace_period
        billing_entity.save!

        Invoices::UpdateAllInvoiceGracePeriodFromBillingEntityJob.perform_later(billing_entity, old_grace_period)
      end

      result.billing_entity = billing_entity
      result
    end

    private

    attr_reader :billing_entity, :grace_period
  end
end
