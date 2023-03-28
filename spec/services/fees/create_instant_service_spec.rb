# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::CreateInstantService, type: :service do
  subject(:fee_service) { described_class.new(charge:, event:, estimate:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:active_subscription, organization:, customer:, plan:) }

  let(:group) { nil }

  let(:charge) { create(:standard_charge, :instant, billable_metric:, plan:) }
  let(:event) { create(:event, subscription:, customer:) }
  let(:estimate) { false }

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
        result.count = 1
        result.units = 9
      end
    end

    before do
      allow(BillableMetrics::InstantAggregationService).to receive(:call)
        .with(billable_metric:, boundaries: Hash, group:, properties: Hash, event:)
        .and_return(aggregation_result)

      allow(Charges::ApplyInstantChargeModelService).to receive(:call)
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
          vat_rate: 20.0,
          vat_amount_cents: 2,
          vat_amount_currency: 'EUR',
          fee_type: 'instant_charge',
          invoiceable: charge,
          units: 9,
          properties: Hash,
          events_count: 1,
          group: nil,
          instant_event_id: event.id,
          payment_status: 'pending',
        )
      end
    end

    it 'delivers a webhook' do
      fee_service.call

      expect(SendWebhookJob).to have_been_enqueued
        .with('fee.instant_created', Fee)
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
          :instant,
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
          subscription:,
          customer:,
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
            vat_rate: 20.0,
            vat_amount_cents: 2,
            vat_amount_currency: 'EUR',
            fee_type: 'instant_charge',
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            group:,
            instant_event_id: event.id,
          )
        end
      end

      context 'when group has a parent' do
        let(:parent_group_id) do
          create(:group, billable_metric:, key: 'cloud', value: 'AWS').id
        end

        let(:event) do
          create(
            :event,
            subscription:,
            customer:,
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
              vat_rate: 20.0,
              vat_amount_cents: 2,
              vat_amount_currency: 'EUR',
              fee_type: 'instant_charge',
              invoiceable: charge,
              units: 9,
              properties: Hash,
              events_count: 1,
              group:,
              instant_event_id: event.id,
            )
          end
        end
      end

      context 'when event does not match a group' do
        let(:event) do
          create(
            :event,
            subscription:,
            customer:,
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
            vat_rate: 20.0,
            vat_amount_cents: 2,
            vat_amount_currency: 'EUR',
            fee_type: 'instant_charge',
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            group: nil,
            instant_event_id: event.id,
          )
        end
      end

      it 'does not deliver a webhook' do
        fee_service.call

        expect(SendWebhookJob).not_to have_been_enqueued
          .with('fee.instant_created', Fee)
      end
    end
  end
end
