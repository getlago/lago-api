# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::RefreshDraftService, type: :service do
  subject(:refresh_service) { described_class.new(credit_note:, fee:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:, rate: 20) }
  let(:invoice) { create(:invoice, organization:, customer:, fees_amount_cents: 100, coupons_amount_cents: 20) }

  describe '#call' do
    let(:status) { :draft }
    let(:credit_note) do
      create(
        :credit_note,
        invoice:,
        status:,
        taxes_rate: 0,
        taxes_amount_cents: 0,
        credit_amount_cents: 100,
        balance_amount_cents: 100,
        total_amount_cents: 100,
      )
    end
    let(:fee) { create(:fee, invoice:, taxes_rate: 20, amount_cents: 100, precise_coupons_amount_cents: 20) }
    let(:applied_tax) { create(:fee_applied_tax, tax:, fee:, amount_cents: 0) }

    before do
      applied_tax
      create(:credit_note_item, credit_note:, fee: create(:fee, invoice:, taxes_rate: 0))
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
        .to change { credit_note.reload.taxes_amount_cents }.from(0).to(16)
        .and change(credit_note, :coupons_adjustment_amount_cents).from(0).to(20)
        .and change(credit_note, :credit_amount_cents).from(100).to(96)
        .and change(credit_note, :balance_amount_cents).from(100).to(96)
        .and change(credit_note, :total_amount_cents).from(100).to(96)
    end
  end
end
