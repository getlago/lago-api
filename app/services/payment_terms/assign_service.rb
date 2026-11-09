# frozen_string_literal: true

module PaymentTerms
  # Applies the alias equivalence matrix to a record's payment term columns.
  # - payment_term object sent: it wins — the jsonb is assigned and the integer
  #   alias is mirrored from it.
  # - payment_term null sent: clears both, unless a non-null net_payment_term comes
  #   with it; then the null is a serialized unset field and the alias is applied.
  # - only net_payment_term sent: the integer is assigned and the jsonb is derived
  #   from it as {term_type: "net", days: N} (nil clears both) — but only when the
  #   alias actually changes, so a term the alias cannot express (alias nil)
  #   survives legacy clients that echo net_payment_term back on every upsert.
  # Assigns without saving; the caller owns persistence.
  class AssignService < BaseService
    Result = BaseResult

    def initialize(record:, params:)
      @record = record
      @params = params
      super
    end

    def call
      if structured_term_sent?
        term = params[:payment_term] && PaymentTerm.from_h(params[:payment_term])
        record.payment_term = term&.to_h
        record.net_payment_term = term&.net_payment_term_alias
      elsif params.key?(:net_payment_term)
        record.net_payment_term = params[:net_payment_term]

        if record.net_payment_term_changed? || record.payment_term.nil?
          # From the cast column value, so input like "" leaves both columns in agreement
          record.payment_term = PaymentTerm.from_net_payment_term(record.net_payment_term)&.to_h
        end
      end

      result
    end

    private

    attr_reader :record, :params

    def structured_term_sent?
      return false unless params.key?(:payment_term)

      !params[:payment_term].nil? || params[:net_payment_term].nil?
    end
  end
end
