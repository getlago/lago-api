# frozen_string_literal: true

module RawPaymentTermParams
  private

  # Strong params drop null and wrong-type values before validation.
  # As a solution, this method copies the raw payment_term into the permitted params,
  # so the PaymentTerms::ValidateService receives every value that the client sent.
  # net_payment_term keeps the strong params behavior: an object or array is dropped, as before
  # payment terms, instead of being cast to nil and clearing the term.
  def with_raw_payment_term(permitted, raw)
    return permitted unless raw.respond_to?(:key?) && raw.key?(:payment_term)

    permitted[:payment_term] = permit_raw_value(raw[:payment_term])
    permitted
  end

  # Wrong-type values reach the validator as they are, so nested parameters (a hash, or
  # hashes inside an array) must be permitted too, or `to_h` raises instead.
  # Keys are not filtered here: PaymentTerms::ValidateService rejects unexpected ones with a 422,
  # and PaymentTerms::AssignService stores only the PaymentTerm fields.
  def permit_raw_value(value)
    case value
    when ActionController::Parameters then value.permit!
    when Array then value.map { |item| permit_raw_value(item) }
    else value
    end
  end
end
