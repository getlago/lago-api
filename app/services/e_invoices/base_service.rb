# frozen_string_literal: true

module EInvoices
  class BaseService < ::BaseService
    COMMERCIAL_INVOICE = 380
    PREPAID_INVOICE = 386
    SELF_BILLED_INVOICE = 389

    # More taxations defined on UNTDID 5153 here
    # https://service.unece.org/trade/untdid/d00a/tred/tred5153.htm
    VAT = "VAT"

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
  end
end
