# frozen_string_literal: true

module Fees
  class PaidCreditService < BaseService
    def initialize(invoice:, wallet_transaction:, customer:)
      @invoice = invoice
      @customer = customer
      @wallet_transaction = wallet_transaction
      super(nil)
    end

    def create
      return result if already_billed?

      currency = invoice.amount.currency
      rounded_amount = wallet_transaction.amount.round(currency.exponent)
      amount_cents = rounded_amount * currency.subunit_to_unit

      new_fee = Fee.new(
        invoice: invoice,
        fee_type: :credit,
        invoiceable_type: 'WalletTransaction',
        invoiceable: wallet_transaction,
        amount_cents: amount_cents,
        amount_currency: wallet_transaction.wallet.currency,
        vat_rate: customer.applicable_vat_rate,
        units: 1,
      )

      new_fee.compute_vat
      new_fee.save!

      result.fee = new_fee
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :wallet_transaction, :customer

    def already_billed?
      existing_fee = invoice.fees.find_by(invoiceable_id: wallet_transaction.id, invoiceable_type: 'WalletTransaction')
      return false unless existing_fee

      result.fee = existing_fee
      true
    end
  end
end
