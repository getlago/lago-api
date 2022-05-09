# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::ChargeService do
  subject(:charge_subscription_service) do
    described_class.new(invoice: invoice, charge: charge)
  end

  let(:subscription) { create(:subscription) }
  let(:invoice) { create(:invoice, subscription: subscription) }
  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      charge_model: 'standard',
      billable_metric: billable_metric,
      amount_cents: 20,
    )
  end

  describe '.create' do
    it 'creates a fee' do
      result = charge_subscription_service.create

      expect(result).to be_success

      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.id).not_to be_nil
        expect(created_fee.invoice_id).to eq(invoice.id)
        expect(created_fee.charge_id).to eq(charge.id)
        expect(created_fee.amount_cents).to eq(0)
        expect(created_fee.amount_currency).to eq('EUR')
        expect(created_fee.vat_amount_cents).to eq(0)
        expect(created_fee.vat_rate).to eq(20.0)
      end
    end

    context 'when fee already exists on the period' do
      before do
        create(
          :fee,
          charge: charge,
          subscription: subscription,
          invoice: invoice,
        )
      end

      it 'does not create a new fee' do
        expect { charge_subscription_service.create }.not_to change(Fee, :count)
      end
    end

    context 'when billing an new upgraded subscription' do
      let(:previous_plan) { create(:plan, amount_cents: subscription.plan.amount_cents - 20) }
      let(:previous_subscription) do
        create(:subscription, plan: previous_plan, status: :terminated)
      end

      let(:event) do
        create(
          :event,
          organization: invoice.organization,
          customer: subscription.customer,
          code: billable_metric.code,
          timestamp: Time.zone.parse('10 Apr 2022 00:01:00'),
        )
      end

      before do
        subscription.update!(previous_subscription: previous_subscription)
        invoice.update!(
          from_date: Time.zone.parse('15 Apr 2022 00:01:00'),
          to_date: Time.zone.parse('30 Apr 2022 00:01:00'),
        )
        event
      end

      it 'creates a new fee for the complete period' do
        result = charge_subscription_service.create

        expect(result).to be_success

        created_fee = result.fee

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.charge_id).to eq(charge.id)
          expect(created_fee.amount_cents).to eq(20)
          expect(created_fee.amount_currency).to eq('EUR')
          expect(created_fee.vat_amount_cents).to eq(4)
          expect(created_fee.vat_rate).to eq(20.0)
        end
      end
    end

    context 'with all types of aggregation' do
      BillableMetric::AGGREGATION_TYPES.each do |aggregation_type|
        before do
          billable_metric.update!(
            aggregation_type: aggregation_type,
            field_name: 'foo_bar',
          )
        end

        it 'creates fees' do
          result = charge_subscription_service.create

          expect(result).to be_success

          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.charge_id).to eq(charge.id)
            expect(created_fee.amount_cents).to eq(0)
            expect(created_fee.amount_currency).to eq('EUR')
            expect(created_fee.vat_amount_cents).to eq(0)
            expect(created_fee.vat_rate).to eq(20.0)
          end
        end
      end
    end
  end
end
