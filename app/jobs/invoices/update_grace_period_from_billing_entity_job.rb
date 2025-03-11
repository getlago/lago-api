# frozen_string_literal: true

module Invoices
  class UpdateGracePeriodFromBillingEntityJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :invoices
      end
    end

    def perform(invoice, old_grace_period)
      Invoices::UpdateGracePeriodFromBillingEntityService.call!(invoice:, old_grace_period:)
    end
  end
end
