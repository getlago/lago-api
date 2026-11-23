# frozen_string_literal: true

module Invoices
  # Records the manual payment of an advance_charges invoice, a receipt for charges already paid.
  class RecordAdvanceChargesPaymentService < BaseService
    Result = BaseResult

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      # Payments::ManualCreateService refuses an amount that is not positive.
      return result unless invoice.advance_charges? && invoice.total_amount_cents.positive?

      ::Payments::ManualCreateJob.perform_later(
        organization: invoice.organization,
        params: {
          invoice_id: invoice.id,
          amount_cents: invoice.total_amount_cents,
          reference: I18n.t("invoice.charges_paid_in_advance"),
          created_at: invoice.created_at
        }
      )

      result
    end

    private

    attr_reader :invoice
  end
end
