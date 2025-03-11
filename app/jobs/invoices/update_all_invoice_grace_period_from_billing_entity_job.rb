# frozen_string_literal: true

module Invoices
  class UpdateAllInvoiceGracePeriodFromBillingEntityJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :invoices
      end
    end

    def perform(billing_entity, old_grace_period)
      Invoices::UpdateAllInvoiceGracePeriodFromBillingEntityService.call!(billing_entity:, old_grace_period:)
    end
  end
end
