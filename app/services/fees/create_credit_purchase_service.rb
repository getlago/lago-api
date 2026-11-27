# frozen_string_literal: true

module Fees
  class CreateCreditPurchaseService < BaseService
    Result = BaseResult[:fee]

    def initialize(invoice:, wallet_transaction:)
      @invoice = invoice
      @wallet_transaction = wallet_transaction
      super
    end

    def call
      currency = wallet_transaction.catalog_wallet.currency
      subunit_to_unit = Money::Currency.new(currency).subunit_to_unit
      purchase_amount_cents = wallet_transaction.purchase_amount_cents
      precise_unit_amount = purchase_amount_cents.to_d / wallet_transaction.credit_amount_cents

      result.fee = Fee.create!(
        invoice:,
        organization_id: invoice.organization_id,
        billing_entity_id: invoice.billing_entity_id,
        fee_type: :credit_purchase,
        invoiceable: wallet_transaction,
        amount_cents: purchase_amount_cents,
        precise_amount_cents: purchase_amount_cents.to_d,
        amount_currency: currency,
        units: wallet_transaction.credit_amount_cents.to_d / subunit_to_unit,
        precise_unit_amount:,
        unit_amount_cents: (precise_unit_amount * subunit_to_unit).round,
        payment_status: :pending,
        taxes_amount_cents: 0
      )
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :wallet_transaction
  end
end
