# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fee, type: :model do
  subject(:fee_model) { described_class }

  describe '.item_code' do
    context 'when it is a subscription fee' do
      let(:subscription) { create(:subscription) }

      it 'returns related subscription code' do
        expect(fee_model.new(subscription:, fee_type: 'subscription').item_code)
          .to eq(subscription.plan.code)
      end
    end

    context 'when it is a charge fee' do
      let(:charge) { create(:standard_charge) }

      it 'returns related billable metric code' do
        expect(fee_model.new(charge:, fee_type: 'charge').item_code)
          .to eq(charge.billable_metric.code)
      end
    end

    context 'when it is a add-on fee' do
      let(:applied_add_on) { create(:applied_add_on) }

      it 'returns add on code' do
        expect(fee_model.new(applied_add_on:, fee_type: 'add_on').item_code)
          .to eq(applied_add_on.add_on.code)
      end
    end

    context 'when it is a credit fee' do
      it 'returns add on code' do
        expect(fee_model.new(fee_type: 'credit').item_code).to eq('credit')
      end
    end

    context 'when it is an pay_in_advance charge fee' do
      let(:charge) { create(:standard_charge, :pay_in_advance) }

      it 'returns related billable metric code' do
        expect(fee_model.new(charge:, fee_type: 'charge').item_code)
          .to eq(charge.billable_metric.code)
      end
    end
  end

  describe '#invoice_name' do
    subject(:fee_invoice_name) { fee.invoice_name }

    context 'when invoice display name is present' do
      let(:fee) { build_stubbed(:fee) }

      it 'returns fee invoice display name' do
        expect(fee_invoice_name).to eq(fee.invoice_display_name)
      end
    end

    context 'when invoice display name is blank' do
      let(:invoice_display_name) { [nil, ''].sample }

      context 'when it is a subscription fee' do
        let(:fee) { build_stubbed(:fee, subscription:, fee_type: 'subscription', invoice_display_name:) }
        let(:subscription) { create(:subscription) }

        it 'returns related subscription name' do
          expect(fee_invoice_name).to eq(subscription.plan.invoice_name)
        end
      end

      context 'when it is a charge fee' do
        let(:fee) { build_stubbed(:fee, charge:, fee_type: 'charge', invoice_display_name:) }
        let(:charge) { create(:standard_charge, invoice_display_name: charge_invoice_display_name) }

        context 'when charge has invoice display name present' do
          let(:charge_invoice_display_name) { Faker::Fantasy::Tolkien.location }

          it 'returns charge invoice display name' do
            expect(fee_invoice_name).to eq(charge.invoice_display_name)
          end
        end

        context 'when charge has invoice display name blank' do
          let(:charge_invoice_display_name) { [nil, ''].sample }

          it 'returns related billable metric name' do
            expect(fee_invoice_name).to eq(charge.billable_metric.name)
          end
        end
      end

      context 'when it is a add-on fee' do
        let(:fee) { build_stubbed(:fee, applied_add_on:, fee_type: 'add_on', invoice_display_name:) }
        let(:applied_add_on) { create(:applied_add_on) }

        it 'returns add on name' do
          expect(fee_invoice_name).to eq(applied_add_on.add_on.invoice_name)
        end
      end

      context 'when it is a credit fee' do
        let(:fee) { build_stubbed(:fee, fee_type: 'credit', invoice_display_name:) }

        it 'returns add on name' do
          expect(fee_invoice_name).to eq('credit')
        end
      end

      context 'when it is an pay_in_advance charge fee' do
        let(:fee) { build_stubbed(:fee, charge:, fee_type: 'charge', invoice_display_name:) }
        let(:charge) { create(:standard_charge, :pay_in_advance, invoice_display_name: charge_invoice_display_name) }

        context 'when charge has invoice display name present' do
          let(:charge_invoice_display_name) { Faker::Fantasy::Tolkien.location }

          it 'returns charge invoice display name' do
            expect(fee_invoice_name).to eq(charge.invoice_display_name)
          end
        end

        context 'when charge has invoice display name blank' do
          let(:charge_invoice_display_name) { [nil, ''].sample }

          it 'returns related billable metric name' do
            expect(fee_invoice_name).to eq(charge.billable_metric.name)
          end
        end
      end
    end
  end

  describe '.item_name' do
    context 'when it is a subscription fee' do
      let(:subscription) { create(:subscription) }

      it 'returns related subscription name' do
        expect(fee_model.new(subscription:, fee_type: 'subscription').item_name)
          .to eq(subscription.plan.name)
      end
    end

    context 'when it is a charge fee' do
      let(:charge) { create(:standard_charge) }

      it 'returns related billable metric name' do
        expect(fee_model.new(charge:, fee_type: 'charge').item_name)
          .to eq(charge.billable_metric.name)
      end
    end

    context 'when it is a add-on fee' do
      let(:applied_add_on) { create(:applied_add_on) }

      it 'returns add on name' do
        expect(fee_model.new(applied_add_on:, fee_type: 'add_on').item_name)
          .to eq(applied_add_on.add_on.name)
      end
    end

    context 'when it is a credit fee' do
      it 'returns add on name' do
        expect(fee_model.new(fee_type: 'credit').item_name).to eq('credit')
      end
    end

    context 'when it is an pay_in_advance charge fee' do
      let(:charge) { create(:standard_charge, :pay_in_advance) }

      it 'returns related billable metric name' do
        expect(fee_model.new(charge:, fee_type: 'charge').item_name)
          .to eq(charge.billable_metric.name)
      end
    end
  end

  describe '#item_type' do
    context 'when it is a subscription fee' do
      let(:subscription) { create(:subscription) }

      it 'returns subscription' do
        expect(fee_model.new(subscription:, fee_type: 'subscription').item_type)
          .to eq('Subscription')
      end
    end

    context 'when it is a charge fee' do
      let(:charge) { create(:standard_charge) }

      it 'returns billable metric' do
        expect(fee_model.new(charge:, fee_type: 'charge').item_type)
          .to eq('BillableMetric')
      end
    end

    context 'when it is a add-on fee' do
      let(:applied_add_on) { create(:applied_add_on) }

      it 'returns add on' do
        expect(fee_model.new(applied_add_on:, fee_type: 'add_on').item_type)
          .to eq('AddOn')
      end
    end

    context 'when it is a credit fee' do
      it 'returns wallet transaction' do
        expect(fee_model.new(fee_type: 'credit').item_type).to eq('WalletTransaction')
      end
    end

    context 'when it is an pay_in_advance charge fee' do
      let(:charge) { create(:standard_charge, :pay_in_advance) }

      it 'returns billable metric' do
        expect(fee_model.new(charge:, fee_type: 'charge').item_type)
          .to eq('BillableMetric')
      end
    end
  end

  describe '#item_id' do
    context 'when it is a subscription fee' do
      let(:subscription) { create(:subscription) }

      it 'returns the subscription id' do
        expect(fee_model.new(subscription:, fee_type: 'subscription').item_id)
          .to eq(subscription.id)
      end
    end

    context 'when it is a charge fee' do
      let(:charge) { create(:standard_charge) }

      it 'returns the billable metric id' do
        expect(fee_model.new(charge:, fee_type: 'charge').item_id)
          .to eq(charge.billable_metric.id)
      end
    end

    context 'when it is a add-on fee' do
      let(:applied_add_on) { create(:applied_add_on) }

      it 'returns the add on id' do
        expect(fee_model.new(applied_add_on:, fee_type: 'add_on').item_id)
          .to eq(applied_add_on.add_on_id)
      end
    end

    context 'when it is a credit fee' do
      let(:wallet_transaction) { create(:wallet_transaction) }

      it 'returns the wallet transaction id' do
        expect(fee_model.new(fee_type: 'credit', invoiceable: wallet_transaction).item_id)
          .to eq(wallet_transaction.id)
      end
    end

    context 'when it is an pay_in_advance charge fee' do
      let(:charge) { create(:standard_charge, :pay_in_advance) }

      it 'returns the billable metric id' do
        expect(fee_model.new(charge:, fee_type: 'charge').item_id)
          .to eq(charge.billable_metric.id)
      end
    end
  end

  describe '#total_amount_cents' do
    let(:fee) { create(:fee, amount_cents: 100, taxes_amount_cents: 20) }

    it 'returns the sum of amount and taxes' do
      expect(fee.total_amount_cents).to eq(120)
    end
  end

  describe '#total_amount_currency' do
    let(:fee) { create(:fee, amount_currency: 'EUR') }

    it { expect(fee.total_amount_currency).to eq('EUR') }
  end
end
