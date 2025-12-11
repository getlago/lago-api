# frozen_string_literal: true

module WalletTransactions
  class ValidateService < BaseValidator
    def valid?
      valid_wallet?
      valid_paid_credits_amount? if args[:paid_credits]
      valid_granted_credits_amount? if args[:granted_credits]
      valid_voided_credits_amount? if args[:voided_credits] && result.current_wallet
      valid_metadata? if args[:metadata]
      valid_name? if args[:name]
      valid_payment_method?

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    MAX_AMOUNT = 10**25 - 1
    private_constant :MAX_AMOUNT

    def valid_amount?(amount)
      ::Validators::DecimalAmountService.new(amount).valid_amount? &&
        BigDecimal(amount).between?(0, MAX_AMOUNT)
    end

    def valid_wallet?
      organization = args[:organization].presence || Organization.find_by(id: args[:organization_id])

      result.current_wallet = organization.wallets.find_by(id: args[:wallet_id])

      return add_error(field: :wallet_id, error_code: "wallet_not_found") unless result.current_wallet
      return add_error(field: :wallet_id, error_code: "wallet_is_terminated") if result.current_wallet.terminated?

      true
    end

    def valid_paid_credits_amount?
      return true if valid_amount?(args[:paid_credits])

      add_error(field: :paid_credits, error_code: "invalid_paid_credits")
      add_error(field: :paid_credits, error_code: "invalid_amount")
    end

    def valid_granted_credits_amount?
      return true if valid_amount?(args[:granted_credits])

      add_error(field: :granted_credits, error_code: "invalid_granted_credits")
      add_error(field: :granted_credits, error_code: "invalid_amount")
    end

    def valid_voided_credits_amount?
      voided_credits = args[:voided_credits]
      unless valid_amount?(voided_credits)
        add_error(field: :voided_credits, error_code: "invalid_voided_credits")
        add_error(field: :voided_credits, error_code: "invalid_amount")
        return false
      end

      if BigDecimal(voided_credits) > result.current_wallet.credits_balance
        return add_error(field: :voided_credits, error_code: "insufficient_credits")
      end

      true
    end

    def valid_metadata?
      validator = ::Validators::MetadataValidator.new(args[:metadata])
      unless validator.valid?
        validator.errors.each do |field, error_code|
          add_error(field: field, error_code: error_code)
        end
        return false
      end

      true
    end

    def valid_name?
      name = args[:name]

      return true if name.blank?

      if !name.is_a?(String)
        add_error(field: :name, error_code: "invalid_value")
        return false
      end

      if name.length > 255
        add_error(field: :name, error_code: "too_long")
        return false
      end

      false
    end

    def valid_payment_method?
      return true if args[:payment_method].blank?
      return true if PaymentMethods::ValidateService.new(result, **args).valid?

      add_error(field: :payment_method, error_code: "invalid_payment_method")

      false
    end
  end
end
