# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::ComputeAmountService, type: :service do
  subject(:amount_service) { described_class.new(invoice:, items:) }

  let(:invoice) do
    create(
      :invoice,
      currency: 'EUR',
      fees_amount_cents: 20,
      coupons_amount_cents: 10,
      vat_amount_cents: 2,
      total_amount_cents: 12,
      payment_status: :succeeded,
      vat_rate: 20,
      version_number: 3,
    )
  end

  let(:items) do
    [
      CreditNoteItem.new(
        fee_id: fee1.id,
        precise_amount_cents: 10,
      ),
      CreditNoteItem.new(
        fee_id: fee2.id,
        precise_amount_cents: 5,
      ),
    ]
  end

  let(:fee1) { create(:fee, invoice:, amount_cents: 10, vat_amount_cents: 1, vat_rate: 20) }
  let(:fee2) { create(:fee, invoice:, amount_cents: 10, vat_amount_cents: 1, vat_rate: 20) }

  describe '.call' do
    it 'computes the credit note amounts' do
      result = amount_service.call

      expect(result).to have_attributes(
        coupons_adjustment_amount_cents: 7.5,
        vat_amount_cents: 1.5,
        creditable_amount_cents: 9,
      )
    end
  end
end
