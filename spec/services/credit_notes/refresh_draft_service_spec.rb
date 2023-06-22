# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::RefreshDraftService, type: :service do
  subject(:refresh_service) { described_class.new(credit_note:, fee:) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      currency: 'EUR',
      fees_amount_cents: 100,
      total_amount_cents: 120,
      coupons_amount_cents: 20,
    )
  end

  describe '#call' do
    let(:status) { :draft }
    let(:credit_note) { create(:credit_note, status:, invoice:) }
    let(:fee) { create(:fee, invoice:, taxes_rate: 0) }

    before do
      create(:credit_note_item, credit_note:, fee: create(:fee, taxes_rate: 20))
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
        .to change { credit_note.reload.taxes_amount_cents }.from(20).to(0)
        .and change(credit_note, :coupons_adjustment_amount_cents).from(0).to(20)
        .and change(credit_note, :credit_amount_cents).from(120).to(80)
        .and change(credit_note, :balance_amount_cents).from(120).to(80)
        .and change(credit_note, :total_amount_cents).from(120).to(80)
    end
  end
end
