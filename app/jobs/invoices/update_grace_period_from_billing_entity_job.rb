# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

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
      Invoices::UpdateIssuingDateFromBillingEntityService.call!(
        invoice:,
        previous_issuing_date_settings: {
          invoice_grace_period: old_grace_period,
          subscription_invoice_issuing_date_anchor: "next_period_start",
          subscription_invoice_issuing_date_adjustment: "align_with_finalization_date"
        }
      )
    end
  end
end
