# frozen_string_literal: true

module Invoices
  class UpdateGracePeriodFromOrganizationJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :invoices
      end
    end

    def perform(invoice, old_grace_period)
      Invoices::UpdateGracePeriodFromOrganizationService.call!(invoice:, old_grace_period:)
    end
  end
end
