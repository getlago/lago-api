# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNote, type: :model do
  subject(:credit_note) { create(:credit_note) }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to have_many(:integration_resources) }

  describe 'sequential_id' do
    let(:invoice) { create(:invoice) }
    let(:customer) { invoice.customer }
    let(:credit_note) { build(:credit_note, invoice:, customer:) }

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
        create(:credit_note, invoice:, sequential_id: 5)
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
        create(:credit_note, sequential_id: 1)
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
    let(:credit_note) { build(:credit_note, invoice:, customer:) }

    it 'generates the credit_note_number' do
      credit_note.save

      expect(credit_note.number).to eq('CUST-001-CN001')
    end
  end

  describe '#currency' do
    let(:credit_note) { build(:credit_note, total_amount_currency: 'JPY') }

    it { expect(credit_note.currency).to eq('JPY') }
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

  describe '#subscription_ids' do
    let(:invoice) { credit_note.invoice }
    let(:subscription_fee) { create(:fee, invoice:) }
    let(:credit_note_item1) do
      create(:credit_note_item, credit_note:, fee: subscription_fee)
    end

    let(:charge_fee) { create(:charge_fee, invoice:) }
    let(:credit_note_item2) do
      create(:credit_note_item, credit_note:, fee: charge_fee)
    end

    before do
      credit_note_item1
      credit_note_item2
    end

    it 'returns the list of subscription ids' do
      expect(credit_note.subscription_ids).to contain_exactly(
        subscription_fee.subscription_id,
        charge_fee.subscription_id,
      )
    end

    context 'with add_on fee' do
      let(:add_on_fee) { create(:add_on_fee, invoice:) }
      let(:credit_note_item3) do
        create(:credit_note_item, credit_note:, fee: add_on_fee)
      end

      before { credit_note_item3 }

      it 'returns an empty subscription id' do
        expect(credit_note.subscription_ids).to include(
          subscription_fee.subscription_id,
          charge_fee.subscription_id,
          nil,
        )
      end
    end

    describe '#subscription_item' do
      let(:invoice) { credit_note.invoice }
      let(:subscription_fee) { create(:fee, invoice:) }
      let(:credit_note_item1) do
        create(:credit_note_item, credit_note:, fee: subscription_fee)
      end

      let(:subscription) { subscription_fee.subscription }
      let(:charge_fee) { create(:charge_fee, invoice:, subscription:) }
      let(:credit_note_item2) do
        create(:credit_note_item, credit_note:, fee: charge_fee)
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
      let(:invoice) { credit_note.invoice }
      let(:subscription_fee) { create(:fee, invoice:) }
      let(:credit_note_item1) do
        create(:credit_note_item, credit_note:, fee: subscription_fee)
      end

      let(:subscription) { subscription_fee.subscription }

      let(:charge_fee) { create(:charge_fee, invoice:, subscription:) }
      let(:credit_note_item2) do
        create(:credit_note_item, credit_note:, fee: charge_fee)
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

  describe '#add_on_items' do
    let(:invoice) { credit_note.invoice }
    let(:add_on) { create(:add_on, organization: credit_note.organization) }
    let(:applied_add_on) { create(:applied_add_on, add_on:) }
    let(:credit_note_item) { create(:credit_note_item, credit_note:, fee: add_on_fee) }
    let(:add_on_fee) { create(:add_on_fee, invoice:, applied_add_on:) }

    before { credit_note_item }

    it 'returns items of the add-on' do
      expect(credit_note.add_on_items).to eq([credit_note_item])
    end
  end

  describe '#voidable?' do
    let(:credit_note) { create(:credit_note, balance_amount_cents:, credit_status:) }
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

  describe ' #sub_total_excluding_taxes_amount_cents' do
    it 'returs the total amount without the taxes' do
      expect(credit_note.sub_total_excluding_taxes_amount_cents)
        .to eq(credit_note.items.sum(&:precise_amount_cents) - credit_note.precise_coupons_adjustment_amount_cents)
    end
  end
end
