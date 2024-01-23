# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::CreatePayInAdvanceService, type: :service do
  subject(:fee_service) { described_class.new(charge:, event:, estimate:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:active_subscription, customer:, plan:) }
  let(:tax) { create(:tax, organization:, rate: 20) }

  let(:group) { nil }

  let(:charge) { create(:standard_charge, :pay_in_advance, billable_metric:, plan:) }
  let(:estimate) { false }

  let(:event) do
    create(
      :event,
      external_subscription_id: subscription.external_id,
      external_customer_id: customer.external_id,
      organization_id: organization.id,
    )
  end

  before { tax }

  describe '#call' do
    let(:aggregation_result) do
      BaseService::Result.new.tap do |result|
        result.aggregation = 9
        result.count = 4
        result.options = {}
      end
    end

    let(:charge_result) do
      BaseService::Result.new.tap do |result|
        result.amount = 10
        result.unit_amount = 0.01111111111
        result.count = 1
        result.units = 9
      end
    end

    before do
      allow(Charges::PayInAdvanceAggregationService).to receive(:call)
        .with(charge:, boundaries: Hash, group:, properties: Hash, event:)
        .and_return(aggregation_result)

      allow(Charges::ApplyPayInAdvanceChargeModelService).to receive(:call)
        .with(charge:, aggregation_result:, properties: Hash)
        .and_return(charge_result)
    end

    it 'creates a fee' do
      result = fee_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.fees.count).to eq(1)
        expect(result.fees.first).to have_attributes(
          subscription:,
          charge:,
          amount_cents: 10,
          amount_currency: 'EUR',
          fee_type: 'charge',
          pay_in_advance: true,
          invoiceable: charge,
          units: 9,
          properties: Hash,
          events_count: 1,
          group: nil,
          pay_in_advance_event_id: event.id,
          payment_status: 'pending',
          unit_amount_cents: 1,
          precise_unit_amount: 0.01111111111,

          taxes_rate: 20.0,
          taxes_amount_cents: 2,
        )
        expect(result.fees.first.applied_taxes.count).to eq(1)
      end
    end

    it 'delivers a webhook' do
      fee_service.call

      expect(SendWebhookJob).to have_been_enqueued
        .with('fee.created', Fee)
    end

    context 'when aggregation fails' do
      let(:aggregation_result) do
        BaseService::Result.new.service_failure!(code: 'failure', message: 'Failure')
      end

      it 'returns a failure' do
        result = fee_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('failure')
          expect(result.error.error_message).to eq('Failure')
        end
      end
    end

    context 'when charge model fails' do
      let(:charge_result) do
        BaseService::Result.new.service_failure!(code: 'failure', message: 'Failure')
      end

      it 'returns a failure' do
        result = fee_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('failure')
          expect(result.error.error_message).to eq('Failure')
        end
      end
    end

    context 'when charge has groups' do
      let(:parent_group_id) { nil }
      let(:group) do
        create(:group, billable_metric:, key: 'region', value: 'europe', parent_group_id:)
      end

      let(:charge) do
        create(
          :standard_charge,
          :pay_in_advance,
          plan: subscription.plan,
          billable_metric:,
          group_properties: [
            build(
              :group_property,
              group:,
              values: {
                amount: '20',
                amount_currency: 'EUR',
              },
            ),
          ],
        )
      end

      let(:event) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          properties: {
            region: 'europe',
          },
        )
      end

      it 'creates a fee' do
        result = fee_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            amount_currency: 'EUR',
            fee_type: 'charge',
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            group:,
            pay_in_advance_event_id: event.id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,

            taxes_rate: 20.0,
            taxes_amount_cents: 2,
          )
          expect(result.fees.first.applied_taxes.count).to eq(1)
        end
      end

      context 'when group has a parent' do
        let(:parent_group_id) do
          create(:group, billable_metric:, key: 'cloud', value: 'AWS').id
        end

        let(:event) do
          create(
            :event,
            organization:,
            external_subscription_id: subscription.external_id,
            external_customer_id: customer.external_id,
            properties: {
              cloud: 'AWS',
              region: 'europe',
            },
          )
        end

        it 'creates a fee' do
          result = fee_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(result.fees.count).to eq(1)
            expect(result.fees.first).to have_attributes(
              subscription:,
              charge:,
              amount_cents: 10,
              amount_currency: 'EUR',
              fee_type: 'charge',
              pay_in_advance: true,
              invoiceable: charge,
              units: 9,
              properties: Hash,
              events_count: 1,
              group:,
              pay_in_advance_event_id: event.id,
              unit_amount_cents: 1,
              precise_unit_amount: 0.01111111111,

              taxes_rate: 20.0,
              taxes_amount_cents: 2,
            )
            expect(result.fees.first.applied_taxes.count).to eq(1)
          end
        end
      end

      context 'when event does not match a group' do
        let(:event) do
          create(
            :event,
            organization:,
            external_subscription_id: subscription.external_id,
            external_customer_id: customer.external_id,
            properties: {
              region: 'usa',
            },
          )
        end

        it 'does not create fees' do
          result = fee_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.fees.count).to be_zero
          end
        end
      end
    end

    context 'when charge has a grouped_by property' do
      let(:charge) do
        create(
          :standard_charge,
          billable_metric:,
          pay_in_advance: true,
          properties: { 'grouped_by' => ['operator'], 'amount' => '100' },
        )
      end

      let(:event) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          properties: { 'operator' => 'foo' },
        )
      end

      it 'creates a fee' do
        result = fee_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            amount_currency: 'EUR',
            fee_type: 'charge',
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            group: nil,
            pay_in_advance_event_id: event.id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,
            grouped_by: { 'operator' => 'foo' },

            taxes_rate: 20.0,
            taxes_amount_cents: 2,
          )
          expect(result.fees.first.applied_taxes.count).to eq(1)
        end
      end
    end

    context 'when in estimate mode' do
      let(:estimate) { true }

      it 'does not persist the fee' do
        result = fee_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).not_to be_persisted
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            amount_currency: 'EUR',
            fee_type: 'charge',
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            group: nil,
            pay_in_advance_event_id: event.id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,

            taxes_rate: 20.0,
            taxes_amount_cents: 2,
          )
          expect(result.fees.first.applied_taxes.size).to eq(1)
        end
      end

      it 'does not deliver a webhook' do
        fee_service.call

        expect(SendWebhookJob).not_to have_been_enqueued
          .with('fee.created', Fee)
      end
    end

    context 'when in current and max aggregation result' do
      let(:aggregation_result) do
        BaseService::Result.new.tap do |result|
          result.amount = 10
          result.count = 1
          result.units = 9
          result.current_aggregation = 9
          result.max_aggregation = 9
          result.max_aggregation_with_proration = nil
        end
      end

      it 'creates a cached aggregation' do
        aggregate_failures do
          expect { fee_service.call }.to change(CachedAggregation, :count).by(1)

          cached_aggregation = CachedAggregation.last
          expect(cached_aggregation.organization_id).to eq(organization.id)
          expect(cached_aggregation.event_id).to eq(event.id)
          expect(cached_aggregation.timestamp.iso8601(3)).to eq(event.timestamp.iso8601(3))
          expect(cached_aggregation.charge_id).to eq(charge.id)
          expect(cached_aggregation.external_subscription_id).to eq(event.external_subscription_id)
          expect(cached_aggregation.group_id).to be_nil
          expect(cached_aggregation.current_aggregation).to eq(9)
          expect(cached_aggregation.max_aggregation).to eq(9)
          expect(cached_aggregation.max_aggregation_with_proration).to be_nil
          expect(cached_aggregation.grouped_by).to eq({})
        end
      end
    end
  end
end
