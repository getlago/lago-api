# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::CreateService, type: :service do
  subject(:create_service) { described_class.new(plan:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }

  before { plan }

  describe '#call' do
    let(:sum_billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
    let(:params) { {} }

    context 'when plan is not found' do
      let(:plan) { nil }

      it 'returns an error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('plan_not_found')
        end
      end
    end

    context 'when charge model is premium' do
      let(:params) do
        {
          billable_metric_id: sum_billable_metric.id,
          charge_model: 'graduated_percentage',
          pay_in_advance: false,
          invoiceable: true,
          properties: {
            graduated_percentage_ranges: [
              {
                from_value: 0,
                to_value: 10,
                rate: '3',
                flat_amount: '0'
              },
              {
                from_value: 11,
                to_value: nil,
                rate: '2',
                flat_amount: '3'
              }
            ]
          }
        }
      end

      it 'returns an error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:charge_model]).to eq(['value_is_mandatory'])
        end
      end

      context 'with premium license' do
        around { |test| lago_premium!(&test) }

        it 'saves premium charge model' do
          create_service.call

          expect(plan.reload.charges.graduated_percentage.first).to have_attributes(
            {
              pay_in_advance: false,
              invoiceable: true,
              charge_model: 'graduated_percentage'
            }
          )
        end
      end

      context 'when charge is successfully added' do
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
            billable_metric_id: sum_billable_metric.id,
            charge_model: 'standard',
            pay_in_advance: false,
            prorated: true,
            invoiceable: false,
            min_amount_cents: 10,
            filters: [
              {
                invoice_display_name: 'Card filter',
                properties: {amount: '90'},
                values: {billable_metric_filter.key => ['card']}
              }
            ]
          }
        end

        it 'creates new charge' do
          expect { create_service.call }.to change(Charge, :count).by(1)
        end

        it 'sets correctly attributes' do
          create_service.call

          stored_charge = plan.reload.charges.first

          expect(stored_charge.reload).to have_attributes(
            prorated: true,
            pay_in_advance: false,
            properties: {'amount' => '0'}
          )

          expect(stored_charge.filters.first).to have_attributes(
            invoice_display_name: 'Card filter',
            properties: {'amount' => '90'}
          )
          expect(stored_charge.filters.first.values.first).to have_attributes(
            billable_metric_filter_id: billable_metric_filter.id,
            values: ['card']
          )
        end

        it 'does not update premium attributes' do
          create_service.call

          stored_charge = plan.reload.charges.first

          expect(stored_charge).to have_attributes(invoiceable: true, min_amount_cents: 0)
        end

        context 'when premium' do
          around { |test| lago_premium!(&test) }

          it 'saves premium attributes' do
            create_service.call

            stored_charge = plan.reload.charges.first

            expect(stored_charge).to have_attributes(invoiceable: false, min_amount_cents: 10)
          end
        end
      end
    end
  end
end
