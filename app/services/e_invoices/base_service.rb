# frozen_string_literal: true

module EInvoices
  class BaseService < ::BaseService
    COMMERCIAL_INVOICE = 380
    PREPAID_INVOICE = 386
    SELF_BILLED_INVOICE = 389

    # More taxations defined on UNTDID 5153 here
    # https://service.unece.org/trade/untdid/d00a/tred/tred5153.htm
    VAT = "VAT"

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

    def payment_information
      case type
      when STANDARD
        payment_label
      when PREPAID, CREDIT_NOTE
        I18n.t("invoice.e_invoicing.payment_information", payment_label:, currency: invoice.currency, amount:)
      end
    end

    def payment_label
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

    def discount_reason
      I18n.t("invoice.e_invoicing.discount_reason", tax_rate: percent(tax_rate))
    end

    def tax_category_code(tax_rate:, type: nil)
      return O_CATEGORY if type == "credit"

      tax_rate.zero? ? Z_CATEGORY : S_CATEGORY
    end
  end
end
