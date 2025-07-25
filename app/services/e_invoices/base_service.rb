module EInvoices
  class BaseService
    COMMERCIAL_INVOICE = 380
    UNITS_CODE = "C62"

    UNKNOWN_PAYMENT_METHOD = 1

    def cbc
      yield xml['cbc']
    end

    def cac
      yield xml['cac']
    end

    def xml
      raise
    end
  end
end