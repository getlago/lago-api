# frozen_string_literal: true

module Fees
  class PaidCreditService < BaseService
    def initialize(invoice:, wallet_transaction:, customer:, plan:)
      @invoice = invoice
      @customer = customer
      @wallet_transaction = wallet_transaction
      @plan = plan
      super(nil)
    end

    def create
      return result if already_billed?

      new_fee = Fee.new(
        invoice: invoice,
        fee_type: :credit,
        invoiceable_type: 'WalletTransaction',
        invoiceable_id: wallet_transaction.id,
        amount_cents: wallet_transaction.amount,
        amount_currency: plan.amount_currency,
        vat_rate: customer.applicable_vat_rate,
        units: 1,
      )

      new_fee.compute_vat
      new_fee.save!

      result.fee = new_fee
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_reader :invoice, :wallet_transaction, :customer, :plan

    def already_billed?
      existing_fee = invoice.fees.find_by(invoiceable_id: wallet_transaction.id, invoiceable_type: 'WalletTransaction')
      return false unless existing_fee

      result.fee = existing_fee
      true
    end
  end
end
