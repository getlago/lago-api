# frozen_string_literal: true

module Invoices
  class UpdateAllInvoiceGracePeriodFromBillingEntityService < BaseService
    def initialize(billing_entity:, old_grace_period:)
      @billing_entity = billing_entity
      @old_grace_period = old_grace_period

      super
    end

    def call
      billing_entity.invoices.draft.find_each do |invoice|
        Invoices::UpdateGracePeriodFromBillingEntityJob.perform_later(invoice, old_grace_period)
      end

      result
    end

    private

    attr_reader :billing_entity, :old_grace_period
  end
end
