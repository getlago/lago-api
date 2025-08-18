# frozen_string_literal: true

module EInvoices
  class BaseService < ::BaseService
    COMMERCIAL_INVOICE = 380
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
    STANDARD = 1
    PREPAID = 57
    CREDIT_NOTE = 97

    INVOICE_DISCOUNT = false
    INVOICE_ADDITIONAL_CHARGE = true

    # More categories for UNTDID 5305 here
    # https://service.unece.org/trade/untdid/d00a/tred/tred5305.htm
    S_CATEGORY = "S"
    O_CATEGORY = "O"
    Z_CATEGORY = "Z"

    # More measures codes defined in UNECE Recommendation 20 here
    # https://docs.peppol.eu/pracc/catalogue/1.0/codelist/UNECERec20/
    UNIT_CODE = "C62"

    def initialize(invoice:)
      super

      @invoice = invoice
    end

    private

    attr_accessor :invoice

    def formatted_date(date)
      date.strftime(self.class::DATEFORMAT)
    end

    def invoice_type_code
      if invoice.credit?
        PREPAID_INVOICE
      elsif invoice.self_billed?
        SELF_BILLED_INVOICE
      else
        COMMERCIAL_INVOICE
      end
    end

    def oldest_charges_from_datetime
      case invoice.invoice_type
      when "one_off", "credit"
        invoice.created_at
      when "subscription"
        invoice.subscriptions.map do |subscription|
          ::Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)
            .charges_from_datetime
        end.min
      end
    end

    def payment_information(type, amount)
      case type
      when STANDARD
        payment_label(type)
      when PREPAID, CREDIT_NOTE
        I18n.t("invoice.e_invoicing.payment_information", payment_label: payment_label(type), currency: invoice.currency, amount:)
      end
    end

    def payment_label(type)
      case type
      when STANDARD
        I18n.t("invoice.e_invoicing.standard_payment")
      when PREPAID
        I18n.t("invoice.prepaid_credits")
      when CREDIT_NOTE
        I18n.t("invoice.credit_notes")
      end
    end

    def credits_and_payments(&block)
      {
        STANDARD => invoice.total_due_amount,
        PREPAID => invoice.prepaid_credit_amount,
        CREDIT_NOTE => invoice.credit_notes_amount
      }.each do |type, amount|
        yield(type, amount) if amount.positive?
      end
    end

    def payment_terms_description
      "#{I18n.t("invoice.payment_term")} #{I18n.t("invoice.payment_term_days", net_payment_term: invoice.net_payment_term)}"
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

    def allowance_charges(&block)
      return unless invoice.coupons_amount_cents.positive?

      sum_by_taxes_rate = invoice.fees.group(:taxes_rate).order(taxes_rate: :asc).sum(:amount_cents)
      total_without_taxes = sum_by_taxes_rate.values.sum
      coupon_proportions = sum_by_taxes_rate.transform_values do |value|
        Money.new((value.to_f / total_without_taxes) * invoice.coupons_amount_cents)
      end
      coupon_proportions.each do |tax_rate, amount|
        yield(tax_rate, amount)
      end
    end

    def applied_taxes(&block)
      if invoice.applied_taxes.empty?
        yield Invoice::AppliedTax.new(fees_amount: invoice.sub_total_excluding_taxes_amount)
      else
        invoice.applied_taxes.each do |applied_tax|
          yield applied_tax
        end
      end
    end

    def line_items(&block)
      invoice.fees.each_with_index do |fee, index|
        yield fee, index + 1
      end
    end

    def total_prepaid_amount
      invoice.prepaid_credit_amount + invoice.credit_notes_amount
    end

    def due_payable_amount
      invoice.total_amount - total_prepaid_amount
    end

    def percent(value)
      format_number(value, "%.2f%%")
    end

    def format_number(value, mask = "%.2f")
      format(mask, value)
    end
  end
end
