# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNote, type: :model do
  describe 'sequential_id' do
    let(:invoice) { create(:invoice) }
    let(:customer) { invoice.customer }

    let(:credit_note) do
      build(:credit_note, invoice: invoice, customer: customer)
    end

    it 'assigns a sequential_id is present' do
      credit_note.save

      aggregate_failures do
        expect(credit_note).to be_valid
        expect(credit_note.sequential_id).to eq(1)
      end
    end

    context 'when sequential_id is present' do
      before { credit_note.sequential_id = 3 }

      it 'does not replace the sequential_id' do
        credit_note.save

        aggregate_failures do
          expect(credit_note).to be_valid
          expect(credit_note.sequential_id).to eq(3)
        end
      end
    end

    context 'when credit note already exists' do
      before do
        create(
          :credit_note,
          invoice: invoice,
          sequential_id: 5,
        )
      end

      it 'takes the next available id' do
        credit_note.save!

        aggregate_failures do
          expect(credit_note).to be_valid
          expect(credit_note.sequential_id).to eq(6)
        end
      end
    end

    context 'with credit note on other invoice' do
      before do
        create(
          :credit_note,
          sequential_id: 1,
        )
      end

      it 'scopes the sequence to the invoice' do
        credit_note.save

        aggregate_failures do
          expect(credit_note).to be_valid
          expect(credit_note.sequential_id).to eq(1)
        end
      end
    end
  end

  describe 'number' do
    let(:invoice) { create(:invoice, number: 'CUST-001') }
    let(:customer) { invoice.customer }
    let(:credit_note) { build(:credit_note, invoice: invoice, customer: customer) }

    it 'generates the credit_note_number' do
      credit_note.save

      expect(credit_note.number).to eq('CUST-001-CN001')
    end
  end

  describe '#credited?' do
    let(:credit_note) { build(:credit_note, credit_amount_cents: 0) }

    it { expect(credit_note).not_to be_credited }

    context 'when credit amount is present' do
      let(:credit_note) { build(:credit_note, credit_amount_cents: 10) }

      it { expect(credit_note).to be_credited }
    end
  end

  describe '#refunded?' do
    let(:credit_note) { build(:credit_note) }

    it { expect(credit_note).not_to be_refunded }
  end

  describe '#refund_amount_cents' do
    let(:credit_note) { build(:credit_note) }

    it { expect(credit_note.refund_amount_cents).to be_zero }
  end

  describe '#vat_amount_cents' do
    # TODO: will change in credit note phase 2
    let(:credit_note) { build(:credit_note) }

    it { expect(credit_note.vat_amount_cents).to be_zero }
  end

  describe '#subscription_ids' do
    let(:credit_note) { create(:credit_note) }
    let(:invoice) { credit_note.invoice }

    let(:subscription_fee) { create(:fee, invoice: invoice) }
    let(:credit_note_item1) do
      create(:credit_note_item, credit_note: credit_note, fee: subscription_fee)
    end

    let(:charge_fee) { create(:charge_fee, invoice: invoice) }
    let(:credit_note_item2) do
      create(:credit_note_item, credit_note: credit_note, fee: charge_fee)
    end

    before do
      credit_note_item1
      credit_note_item2
    end

    it 'returns the list of subscription ids' do
      expect(credit_note.subscription_ids).to eq([subscription_fee.subscription_id, charge_fee.subscription_id])
    end

    context 'with add_on fee' do
      let(:add_on_fee) { create(:add_on_fee, invoice: invoice) }
      let(:credit_note_item3) do
        create(:credit_note_item, credit_note: credit_note, fee: add_on_fee)
      end

      before { credit_note_item3 }

      it 'returns an empty subscription id' do
        expect(credit_note.subscription_ids).to eq(
          [
            subscription_fee.subscription_id,
            charge_fee.subscription_id,
            nil,
          ],
        )
      end
    end

    describe '#subscription_item' do
      let(:credit_note) { create(:credit_note) }
      let(:invoice) { credit_note.invoice }

      let(:subscription_fee) { create(:fee, invoice: invoice) }
      let(:credit_note_item1) do
        create(:credit_note_item, credit_note: credit_note, fee: subscription_fee)
      end

      let(:subscription) { subscription_fee.subscription }

      let(:charge_fee) { create(:charge_fee, invoice: invoice, subscription: subscription) }
      let(:credit_note_item2) do
        create(:credit_note_item, credit_note: credit_note, fee: charge_fee)
      end

      before do
        credit_note_item1
        credit_note_item2
      end

      it 'returns the item for the subscription fee' do
        expect(credit_note.subscription_item(subscription.id)).to eq(credit_note_item1)
      end

      context 'when subscription id does not match an existing fee' do
        let(:missing_subscription) { create(:subscription) }

        it 'returns a new fee' do
          fee = credit_note.subscription_item(missing_subscription.id)

          expect(fee).to be_new_record
        end
      end
    end

    describe '#subscription_charge_items' do
      let(:credit_note) { create(:credit_note) }
      let(:invoice) { credit_note.invoice }

      let(:subscription_fee) { create(:fee, invoice: invoice) }
      let(:credit_note_item1) do
        create(:credit_note_item, credit_note: credit_note, fee: subscription_fee)
      end

      let(:subscription) { subscription_fee.subscription }

      let(:charge_fee) { create(:charge_fee, invoice: invoice, subscription: subscription) }
      let(:credit_note_item2) do
        create(:credit_note_item, credit_note: credit_note, fee: charge_fee)
      end

      before do
        credit_note_item1
        credit_note_item2
      end

      it 'returns the item for the subscription fee' do
        expect(credit_note.subscription_charge_items(subscription.id)).to eq([credit_note_item2])
      end
    end
  end

  describe '#voidable?' do
    let(:credit_note) do
      create(:credit_note, balance_amount_cents: balance_amount_cents, credit_status: credit_status)
    end

    let(:balance_amount_cents) { 10 }
    let(:credit_status) { :available }

    it { expect(credit_note).to be_voidable }

    context 'when balance is consumed' do
      let(:balance_amount_cents) { 0 }

      it { expect(credit_note).not_to be_voidable }
    end

    context 'when already voided' do
      let(:credit_status) { :voided }

      it { expect(credit_note).not_to be_voidable }
    end
  end
end
