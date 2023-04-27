# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::RefreshDraftService, type: :service do
  subject(:refresh_service) { described_class.new(credit_note:, fee:) }

  describe '#call' do
    let(:status) { :draft }
    let(:credit_note) { create(:credit_note, status:) }
    let(:fee) { create(:fee, vat_rate: 0) }

    before do
      create(:credit_note_item, credit_note:, fee: create(:fee, vat_rate: 20))
    end

    context 'when credit_note is finalized' do
      let(:status) { :finalized }

      it 'does not refresh it' do
        expect { refresh_service.call }.not_to change(credit_note, :updated_at)
      end
    end

    it 'assigns credit note to the fee' do
      expect { refresh_service.call }.to change { credit_note.reload.items.pluck(:fee_id) }.to([fee.id])
    end

    it 'updates vat amounts of the credit note' do
      expect { refresh_service.call }
        .to change { credit_note.reload.vat_amount_cents }.from(20).to(0)
        .and change(credit_note, :credit_amount_cents).from(120).to(100)
        .and change(credit_note, :balance_amount_cents).from(120).to(100)
        .and change(credit_note, :total_amount_cents).from(120).to(100)
    end
  end
end
