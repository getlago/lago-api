# frozen_string_literal: true

module V2
  # The usage accumulating on a contract, one entry per card on its open billing window. The
  # totals add up windows that land on different invoices, so they do not preview an invoice.
  class ContractUsageSerializer < ModelSerializer
    def serialize
      {
        external_contract_id: contract.external_id,
        external_customer_id: contract.customer.external_id,
        currency: contract.currency,
        amount_cents: model.amount_cents,
        taxes_amount_cents: model.taxes_amount_cents,
        total_amount_cents: model.total_amount_cents,
        rate_cards: model.card_windows.map { |window| ::V2::ContractUsageRateCardSerializer.new(window).serialize }
      }
    end

    private

    def contract
      options.fetch(:contract)
    end
  end
end
