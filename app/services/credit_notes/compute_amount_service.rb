# frozen_string_literal: true

module CreditNotes
  class ComputeAmountService < BaseService
    def initialize(invoice:, items:)
      @invoice = invoice
      @items = items

      super
    end

    def call
      result.coupons_adjustment_amount_cents = coupons_adjustment_amount_cents
      result.vat_amount_cents = vat_amount_cents
      result.creditable_amount_cents = creditable_amount_cents
      result
    end

    private

    attr_reader :invoice, :items

    def items_amount_cents
      @items_amount_cents ||= items.map(&:precise_amount_cents).sum
    end

    def coupons_adjustment_amount_cents
      return 0 if invoice.version_number < Invoice::COUPON_BEFORE_VAT_VERSION

      invoice.coupons_amount_cents.fdiv(invoice.fees_amount_cents) * items_amount_cents
    end

    def vat_amount_cents
      items.map do |item|
        # NOTE: Because coupons are applied before VAT,
        #       we have to discribute the coupon adjustement at prorata of each items
        #       to compute the VAT
        item_rate = item.precise_amount_cents.fdiv(items_amount_cents)
        prorated_coupon_amount = coupons_adjustment_amount_cents * item_rate
        (item.precise_amount_cents - prorated_coupon_amount) * (item.fee.vat_rate || 0)
      end.sum.fdiv(100)
    end

    def creditable_amount_cents
      (items_amount_cents - coupons_adjustment_amount_cents + vat_amount_cents).round
    end
  end
end
