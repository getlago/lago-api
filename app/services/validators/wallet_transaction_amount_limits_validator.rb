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
      return true if credits_amount.blank?
      return true if ignore_validation
      return true if paid_top_up_min_amount_cents.blank? && paid_top_up_max_amount_cents.blank?

      wallet_credit = WalletCredit.new(wallet: wallet, credit_amount: credits_amount)

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
  end
end
