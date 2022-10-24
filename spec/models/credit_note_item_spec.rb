# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNoteItem, type: :model do
  describe '#total_amount_cents' do
    let(:item) { create(:credit_note_item) }

    it 'returns the credit and refund amounts' do
      expect(item.total_amount_cents).to eq(
        item.credit_amount_cents + item.refund_amount_cents,
      )
    end
  end

  describe '#total_amount_currency' do
    let(:item) { create(:credit_note_item, credit_amount_currency: 'JPY') }

    it { expect(item.total_amount_currency).to eq('JPY') }
  end
end
