# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::UpdateService, type: :service do
  subject(:update_service) { described_class.new(charge:, params:, cascade:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:cascade) { false }

  describe '#call' do
    let(:sum_billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
    let(:charge) do
      create(
        :standard_charge,
        plan_id: plan.id,
        billable_metric_id: sum_billable_metric.id,
        amount_currency: 'USD',
        properties: {
          amount: '300'
        }
      )
    end
    let(:billable_metric_filter) do
      create(
        :billable_metric_filter,
        billable_metric: sum_billable_metric,
        key: 'payment_method',
        values: %w[card physical]
      )
    end
    let(:params) do
      {
        id: charge&.id,
        billable_metric_id: sum_billable_metric.id,
        charge_model: 'standard',
        pay_in_advance: true,
        prorated: true,
        invoiceable: false,
        filters: [
          {
            invoice_display_name: 'Card filter',
            properties: {amount: '90'},
            values: {billable_metric_filter.key => ['card']}
          }
        ]
      }
    end

    before { charge }

    context 'when charge is not found' do
      let(:charge) { nil }

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('charge_not_found')
        end
      end
    end

    it 'updates existing charge' do
      update_service.call

      expect(charge.reload).to have_attributes(
        prorated: true,
        properties: {'amount' => '0'}
      )

      expect(charge.filters.first).to have_attributes(
        invoice_display_name: 'Card filter',
        properties: {'amount' => '90'}
      )
      expect(charge.filters.first.values.first).to have_attributes(
        billable_metric_filter_id: billable_metric_filter.id,
        values: ['card']
      )
    end

    it 'does not update premium attributes' do
      update_service.call

      expect(charge.reload).to have_attributes(pay_in_advance: true, invoiceable: true)
    end

    context 'when premium' do
      around { |test| lago_premium!(&test) }

      it 'saves premium attributes' do
        update_service.call

        expect(charge.reload).to have_attributes(pay_in_advance: true, invoiceable: false)
      end
    end

    context 'when cascade is true' do
      let(:cascade) { true }

      it 'updates only charge properties' do
        update_service.call

        expect(charge.reload).to have_attributes(
          properties: {'amount' => '0'}
        )

        expect(charge.filters.count).to eq(0)
      end
    end
  end
end
