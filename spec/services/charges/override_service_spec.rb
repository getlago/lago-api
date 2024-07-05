# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::OverrideService, type: :service do
  subject(:override_service) { described_class.new(charge:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe '#call' do
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:tax) { create(:tax, organization:) }

    let(:charge) do
      create(
        :standard_charge,
        billable_metric:,
        properties: {amount: '300'}
      )
    end
    let(:plan) { create(:plan, organization:) }
    let(:params) do
      {
        id: charge.id,
        plan_id: plan.id,
        # invoice_display_name: 'invoice display name',
        min_amount_cents: 1000,
        properties: {amount: '200'},
        tax_codes: [tax.code]
      }
    end

    before { charge }

    context 'when lago freemium' do
      it 'returns without overriding the charge' do
        expect { override_service.call }.not_to change(Charge, :count)
      end
    end

    context 'when lago premium' do
      around { |test| lago_premium!(&test) }

      it 'creates a charge based on the given charge', :aggregate_failures do
        applied_tax = create(:charge_applied_tax, charge:)

        expect(charge.taxes).to contain_exactly(applied_tax.tax)

        expect { override_service.call }.to change(Charge, :count).by(1)

        charge = Charge.order(:created_at).last
        expect(charge).to have_attributes(
          amount_currency: charge.amount_currency,
          billable_metric_id: charge.billable_metric.id,
          charge_model: charge.charge_model,
          invoiceable: charge.invoiceable,
          pay_in_advance: charge.pay_in_advance,
          prorated: charge.prorated,
          # Overriden attributes
          plan_id: plan.id,
          # invoice_display_name: 'invoice display name',
          min_amount_cents: 1000,
          properties: {'amount' => '200'}
        )
        expect(charge.taxes).to contain_exactly(tax)
      end

      context 'with charge filters' do
        let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:) }

        let(:charge) do
          create(
            :standard_charge,
            billable_metric:,
            properties: {amount: '300'}
          )
        end

        let(:filters) do
          [
            create(
              :charge_filter,
              charge:,
              properties: {amount: '10'}
            ),
            create(
              :charge_filter,
              charge:,
              properties: {amount: '20'}
            )
          ]
        end

        let(:filter_values) do
          [
            create(
              :charge_filter_value,
              charge_filter: filters.first,
              billable_metric_filter:,
              values: [billable_metric_filter.values.first]
            ),
            create(
              :charge_filter_value,
              charge_filter: filters.second,
              billable_metric_filter:,
              values: [billable_metric_filter.values.second]
            )
          ]
        end

        let(:params) do
          {
            id: charge.id,
            plan_id: plan.id,
            min_amount_cents: 1000,
            properties: {amount: '200'},
            tax_codes: [tax.code],
            filters: [
              {
                properties: {amount: '10'},
                invoice_display_name: 'invoice display name',
                values: {billable_metric_filter.key => [billable_metric_filter.values.first]}
              }
            ]
          }
        end

        before { filter_values }

        it 'creates a charge based on the given charge', :aggregate_failures do
          expect { override_service.call }.to change(Charge, :count).by(1)

          charge = Charge.order(:created_at).last

          expect(charge.filters.count).to eq(1)
          expect(charge.filters.with_discarded.discarded.count).to eq(1)
          expect(charge.filters.first).to have_attributes(
            {
              invoice_display_name: 'invoice display name',
              properties: {'amount' => '10'}
            }
          )
          expect(charge.filters.first.values.count).to eq(1)
          expect(charge.filters.first.values.first).to have_attributes(
            billable_metric_filter_id: billable_metric_filter.id,
            values: [billable_metric_filter.values.first]
          )
        end
      end
    end
  end
end
