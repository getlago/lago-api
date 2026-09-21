# frozen_string_literal: true

module RawPaymentTermParams
  private

  # Strong params drop null and wrong-type values before validation.
  # As a solution, this method copies raw values into the permitted params,
  # so the PaymentTerms::ValidateService receives every value that the client sent.
  def with_raw_payment_term(permitted, raw)
    %i[payment_term net_payment_term].each do |key|
      next unless raw.respond_to?(:key?) && raw.key?(key)

      permitted[key] = raw[key]
      permitted[key].permit! if permitted[key].is_a?(ActionController::Parameters)
    end

    permitted
  end
end
