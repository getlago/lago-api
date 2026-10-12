# frozen_string_literal: true

module RawPaymentTermParams
  private

  # Strong params drop null and wrong-type values before validation.
  # As a solution, this method copies raw values into the permitted params,
  # so the PaymentTerms::ValidateService receives every value that the client sent.
  def with_raw_payment_term(permitted, raw)
    %i[payment_term net_payment_term].each do |key|
      next unless raw.respond_to?(:key?) && raw.key?(key)

      permitted[key] = permit_raw_value(raw[key])
    end

    permitted
  end

  # Wrong-type values reach the validator as they are, so nested parameters (a hash, or
  # hashes inside an array) must be permitted too, or `to_h` raises instead.
  def permit_raw_value(value)
    case value
    when ActionController::Parameters then value.permit!
    when Array then value.map { |item| permit_raw_value(item) }
    else value
    end
  end
end
