# frozen_string_literal: true

module Validators
  class WalletTransactionAmountLimitsValidator
    def initialize(result, wallet:, credits_amount:, ignore_validation: false)
      @result = result
      @wallet = wallet
      @credits_amount = credits_amount
      @ignore_validation = ActiveModel::Type::Boolean.new.cast(ignore_validation)
    end

    def valid?
      return false unless valid_paid_credits_amount?
      return true if ignore_validation
      return true if paid_top_up_min_amount_cents.blank? && paid_top_up_max_amount_cents.blank?

      wallet_credit = WalletCredit.new(
        wallet:,
        credit_amount: BigDecimal(credits_amount).floor(5)
      )

      return true if wallet_credit.amount_cents.zero?

      if paid_top_up_min_amount_cents && wallet_credit.amount_cents < paid_top_up_min_amount_cents
        result.single_validation_failure!(error_code: "amount_below_minimum", field: :paid_credits)
      elsif paid_top_up_max_amount_cents && wallet_credit.amount_cents > paid_top_up_max_amount_cents
        result.single_validation_failure!(error_code: "amount_above_maximum", field: :paid_credits)
      end

      result.success?
    end

    private

    attr_reader :result, :wallet, :credits_amount, :ignore_validation
    delegate :paid_top_up_min_amount_cents, :paid_top_up_max_amount_cents, to: :wallet

    def valid_paid_credits_amount?
      return true if ::Validators::DecimalAmountService.new(credits_amount).valid_amount?

      result.single_validation_failure!(error_code: "invalid_amount", field: :paid_credits)
      false
    end
  end
end
