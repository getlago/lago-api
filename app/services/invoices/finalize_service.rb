# frozen_string_literal: true

module Invoices
  class FinalizeService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") if invoice.nil?

      if invoice.finalized?
        result.invoice = invoice
        return result
      end

      # A non-zero draft is reserved in the wallet ongoing balance until it leaves draft
      reserved_draft = invoice.draft? && invoice.total_amount_cents != 0

      invoice.finalized!
      invoice.customer.flag_wallets_for_refresh if reserved_draft

      Invoices::RefreshSearchTermsService.call!(invoice:)

      result.invoice = invoice
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice
  end
end
