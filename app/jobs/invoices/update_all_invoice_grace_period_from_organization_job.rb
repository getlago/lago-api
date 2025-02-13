# frozen_string_literal: true

module Invoices
  class UpdateAllInvoiceGracePeriodFromOrganizationJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :invoices
      end
    end

    def perform(organization, old_grace_period)
      Invoices::UpdateAllInvoiceGracePeriodFromOrganizationService.call!(organization:, old_grace_period:)
    end
  end
end
