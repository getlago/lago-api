# frozen_string_literal: true

module BillingSegments
  class RefreshDraftService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:, context:)
      @invoice = invoice
      @context = context
      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice
      return result.forbidden_failure! unless invoice.subscription?

      result.invoice = invoice
      return result unless invoice.draft?

      old_total_amount_cents = invoice.total_amount_cents

      ActiveRecord::Base.transaction do
        reset_invoice

        BillingSegments::ComputeInvoiceService.call!(
          invoice:,
          billing_segments:,
          context:
        )

        if old_total_amount_cents != invoice.total_amount_cents
          invoice.customer.flag_wallets_for_refresh
        end
      end

      result.invoice = invoice.reload
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :invoice, :context

    def billing_segments
      @billing_segments ||= invoice.billing_segments.includes(
        :pricing_unit,
        :rate_override,
        :contract,
        contract_rate_card: {rate_card: :product},
        rate_card_rate: :rate_card
      )
    end

    def reset_invoice
      invoice.fees.discard_all!
      invoice.applied_taxes.destroy_all
      invoice.error_details.discard_all # rubocop:disable Lago/DiscardAll

      invoice.assign_attributes(
        ready_to_be_refreshed: false,
        taxes_amount_cents: 0,
        total_amount_cents: 0,
        taxes_rate: 0,
        fees_amount_cents: 0,
        sub_total_excluding_taxes_amount_cents: 0,
        sub_total_including_taxes_amount_cents: 0
      )
      invoice.save!
    end
  end
end
