# frozen_string_literal: true

module EInvoices
  class BaseService < ::BaseService
    # More document types defined on UNCL 1001 here
    # https://service.unece.org/trade/untdid/d99a/uncl/uncl1001.htm
    COMMERCIAL_INVOICE = 380
    CREDIT_NOTE = 381
    PREPAID_INVOICE = 386
    SELF_BILLED_INVOICE = 389

    # More taxations defined on UNTDID 5153 here
    # https://service.unece.org/trade/untdid/d00a/tred/tred5153.htm
    VAT = "VAT"

    # More VAT exemptions codes
    # https://docs.peppol.eu/poacc/billing/3.0/codelist/vatex/
    O_VAT_EXEMPTION = "VATEX-EU-O"

    # You can see more payments codes UNTDID 4461 here
    # https://service.unece.org/trade/untdid/d21b/tred/tred4461.htm
    STANDARD_PAYMENT = 1
    PREPAID_PAYMENT = 57
    CREDIT_NOTE_PAYMENT = 97

    INVOICE_DISCOUNT = false
    INVOICE_CHARGE = true

    # More categories for UNTDID 5305 here
    # https://service.unece.org/trade/untdid/d00a/tred/tred5305.htm
    S_CATEGORY = "S"
    O_CATEGORY = "O"
    Z_CATEGORY = "Z"

    # More measures codes defined in UNECE Recommendation 20 here
    # https://docs.peppol.eu/pracc/catalogue/1.0/codelist/UNECERec20/
    UNIT_CODE = "C62"

    private

    attr_accessor :invoice

    def formatted_date(date)
      date.strftime(self.class::DATEFORMAT)
    end

    def payment_information(type, amount)
      case type
      when STANDARD_PAYMENT
        payment_label(type)
      when PREPAID_PAYMENT, CREDIT_NOTE_PAYMENT
        I18n.t("invoice.e_invoicing.payment_information", payment_label: payment_label(type), currency: resource.currency, amount:)
      end
    end

    def payment_label(type)
      case type
      when STANDARD_PAYMENT
        I18n.t("invoice.e_invoicing.standard_payment")
      when PREPAID_PAYMENT
        I18n.t("invoice.prepaid_credits")
      when CREDIT_NOTE_PAYMENT
        I18n.t("invoice.credit_notes")
      end
    end

    def line_item_description
      return fee.invoice_name if fee.invoice_name.present?

      I18n.t(
        "invoice.subscription_interval",
        plan_interval: I18n.t("invoice.#{fee.subscription.plan.interval}"),
        plan_name: fee.subscription.plan.invoice_name
      )
    end

    def discount_reason
      I18n.t("invoice.e_invoicing.discount_reason", tax_rate: percent(tax_rate))
    end

    def tax_category_code(tax_rate:, type: nil)
      return O_CATEGORY if type == "credit"

      tax_rate.zero? ? Z_CATEGORY : S_CATEGORY
    end

    def allowances(invoice)
      invoice.coupons_amount_cents + invoice.progressive_billing_credit_amount_cents
    end

    def allowances_per_tax_rate(invoice)
      invoice.fees.group_by(&:taxes_rate).map do |tax_rate, fees|
        total_amount = fees.sum(&:precise_amount_cents)

        if tax_rate > 0
          total_taxes = fees.sum(&:taxes_precise_amount_cents)
          charged_amount = (total_taxes * 100).fdiv(tax_rate)

          [tax_rate, total_amount - charged_amount]
        else
          [tax_rate, total_amount.fdiv(invoice.fees.sum(:precise_amount_cents)) * allowances(invoice)]
        end
      end.to_h
    end

    def allowance_charges(invoice, &block)
      allowances_per_tax_rate(invoice).each_pair do |tax_rate, amount|
        next if amount.zero?

        yield tax_rate, Money.new(amount)
      end
    end

    def taxes(invoice, &block)
      invoice.fees.group_by(&:taxes_rate).map do |tax_rate, fees|
        total_taxes = fees.sum(&:taxes_precise_amount_cents)
        charged_amount = if tax_rate > 0
          (total_taxes * 100).fdiv(tax_rate)
        else
          fees.sum(&:precise_amount_cents) - allowances_per_tax_rate(invoice)[tax_rate]
        end

        tax_category = tax_category_code(type: invoice.invoice_type, tax_rate: tax_rate)

        yield tax_category, tax_rate, Money.new(charged_amount), Money.new(total_taxes)
      end
    end

    def line_items(&block)
      resource.fees.order(amount_cents: :asc).each_with_index do |fee, index|
        yield fee, index + 1
      end
    end

    def fee_description(fee)
      return fee.invoice_name if fee.invoice_name.present?

      I18n.t(
        "invoice.subscription_interval",
        plan_interval: I18n.t("invoice.#{fee.subscription.plan.interval}"),
        plan_name: fee.subscription.plan.invoice_name
      )
    end

    def percent(value)
      format_number(value, "%.2f%%")
    end

    def format_number(value, mask = "%.2f")
      format(mask, value)
    end
  end
end
