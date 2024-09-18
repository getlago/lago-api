# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::CalculateItemsAvailableAmountsService, type: :service do
  subject(:credit_service) { described_class.new(credit_note:) }

  let(:credit_note) do
    create(:credit_note,
      balance_amount_cents: 60000,
      credit_amount_cents: 60000,
      total_amount_cents: 60000,
      taxes_amount_cents: 10000,
      taxes_rate: 20)
  end
  let(:item1) { create(:credit_note_item, credit_note: credit_note, amount_cents: 20000) }
  let(:item2) { create(:credit_note_item, credit_note: credit_note, amount_cents: 30000) }

  before do
    item1
    item2
    credit_note.reload
  end

  context 'when credit_note has balance_amount_cents equal to taxes_amount_cents' do
    it 'calculates items available amounts' do
      result = credit_service.call
      expect(result.available_amounts).to eq({item1.id => 20000, item2.id => 30000})
    end
  end

  context 'when credit_note has balance_amount_cents not equal to taxes_amount_cents' do
    let(:credit_note) do
      create(:credit_note,
        balance_amount_cents: 36000,
        credit_amount_cents: 60000,
        total_amount_cents: 60000,
        taxes_amount_cents: 10000,
        taxes_rate: 20)
    end

    it 'calculates items available amounts' do
      result = credit_service.call
      expect(result.available_amounts).to eq({item1.id => 12000, item2.id => 18000})
    end
  end

  context 'when credit_note has been partially refunded' do
    let(:credit_note) do
      create(:credit_note,
        balance_amount_cents: 36000,
        credit_amount_cents: 60000,
        total_amount_cents: 120000,
        taxes_amount_cents: 20000,
        taxes_rate: 20)
    end
    let(:item1) { create(:credit_note_item, credit_note: credit_note, amount_cents: 40000) }
    let(:item2) { create(:credit_note_item, credit_note: credit_note, amount_cents: 60000) }

    it 'calculates items available amounts with info that they are partially refunded' do
      result = credit_service.call
      expect(result.available_amounts).to eq({item1.id => 12000, item2.id => 18000})
    end
  end
end
