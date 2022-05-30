# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::ChargeService do
  subject(:charge_subscription_service) do
    described_class.new(invoice: invoice, charge: charge)
  end

  let(:subscription) do
    create(
      :subscription,
      status: :active,
      started_at: DateTime.parse('2022-03-15'),
    )
  end

  let(:invoice) do
    create(
      :invoice,
      subscription: subscription,
      from_date: subscription.started_at,
      to_date: subscription.started_at.end_of_month,
    )
  end

  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      billable_metric: billable_metric,
      properties: {
        amount: '20',
        amount_currency: 'EUR',
      },
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
        expect(created_fee.units).to eq(0)
      end
    end

    context 'with graduated charge model' do
      let(:charge) do
        create(
          :graduated_charge,
          plan: subscription.plan,
          charge_model: 'graduated',
          billable_metric: billable_metric,
          properties: [
            {
              from_value: 0,
              to_value: nil,
              per_unit_amount: '0.01',
              flat_amount: '0.01',
            },
          ],
        )
      end

      before do
        create_list(
          :event,
          4,
          organization: subscription.organization,
          customer: subscription.customer,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
        )
      end

      it 'creates a fee' do
        result = charge_subscription_service.create

        expect(result).to be_success

        created_fee = result.fee

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.charge_id).to eq(charge.id)
          expect(created_fee.amount_cents).to eq(5)
          expect(created_fee.amount_currency).to eq('EUR')
          expect(created_fee.vat_amount_cents).to eq(1)
          expect(created_fee.vat_rate).to eq(20.0)
          expect(created_fee.units.to_s).to eq('4.0')
        end
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
          expect(created_fee.amount_cents).to eq(2000)
          expect(created_fee.amount_currency).to eq('EUR')
          expect(created_fee.vat_amount_cents).to eq(400)
          expect(created_fee.vat_rate).to eq(20.0)
          expect(created_fee.units).to eq(1)
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
            expect(created_fee.units).to eq(0)
          end
        end
      end
    end

    context 'with aggregation error' do
      let(:billable_metric) do
        create(
          :billable_metric,
          aggregation_type: 'max_agg',
          field_name: 'foo_bar',
        )
      end
      let(:aggregator_service) { instance_double(BillableMetrics::Aggregations::MaxService) }
      let(:error_result) { BaseService::Result.new.fail!('aggregation_failure') }

      it 'returns an error' do
        allow(BillableMetrics::Aggregations::MaxService).to receive(:new)
          .and_return(aggregator_service)
        allow(aggregator_service).to receive(:aggregate)
          .and_return(error_result)

        result = charge_subscription_service.create

        expect(result).not_to be_success
        expect(result.error_code).to eq('aggregation_failure')

        expect(BillableMetrics::Aggregations::MaxService).to have_received(:new)
        expect(aggregator_service).to have_received(:aggregate)
      end
    end
  end
end
