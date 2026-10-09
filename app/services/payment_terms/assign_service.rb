# frozen_string_literal: true

module PaymentTerms
  # Applies the alias equivalence matrix to a record's payment term columns.
  # - payment_term sent (object or nil): it wins — the jsonb is assigned and
  #   the integer alias is mirrored from it (nil clears both).
  # - only net_payment_term sent: the integer is assigned and the jsonb is
  #   derived from it as {term_type: "net", days: N} (nil clears both).
  # Assigns without saving; the caller owns persistence.
  class AssignService < BaseService
    Result = BaseResult

    def initialize(record:, params:)
      @record = record
      @params = params
      super
    end

    def call
      if params.key?(:payment_term)
        term = params[:payment_term] && PaymentTerm.from_h(params[:payment_term])
        record.payment_term = term&.to_h
        record.net_payment_term = term&.net_payment_term_alias
      elsif params.key?(:net_payment_term)
        record.net_payment_term = params[:net_payment_term]
        record.payment_term = PaymentTerm.from_net_payment_term(params[:net_payment_term])&.to_h
      end

      result
    end

    private

    attr_reader :record, :params
  end
end
