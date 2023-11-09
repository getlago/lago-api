# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::UpdateService, type: :service do
  subject(:plans_service) { described_class.new(plan:, params: update_args) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:plan_name) { 'Updated plan name' }
  let(:plan_invoice_display_name) { 'Updated plan invoice display name' }
  let(:group) { create(:group, billable_metric: sum_billable_metric) }
  let(:sum_billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:tax1) { create(:tax, organization:) }
  let(:applied_tax) { create(:plan_applied_tax, plan:, tax: tax1) }
  let(:tax2) { create(:tax, organization:) }

  let(:update_args) do
    {
      name: plan_name,
      invoice_display_name: plan_invoice_display_name,
      code: 'new_plan',
      interval: 'monthly',
      pay_in_advance: false,
      amount_cents: 200,
      amount_currency: 'EUR',
      tax_codes: [tax2.code],
      charges: charges_args,
    }
  end

  let(:charges_args) do
    [
      {
        billable_metric_id: sum_billable_metric.id,
        charge_model: 'standard',
        invoice_display_name: 'charge1',
        min_amount_cents: 100,
        group_properties: [
          {
            group_id: group.id,
            values: { amount: '100' },
          },
        ],
        tax_codes: [tax1.code],
      },
      {
        billable_metric_id: billable_metric.id,
        charge_model: 'graduated',
        invoice_display_name: 'charge2',
        properties: {
          graduated_ranges: [
            {
              from_value: 0,
              to_value: 10,
              per_unit_amount: '2',
              flat_amount: '0',
            },
            {
              from_value: 11,
              to_value: nil,
              per_unit_amount: '3',
              flat_amount: '3',
            },
          ],
        },
      },
    ]
  end

  describe 'call' do
    before do
      applied_tax
    end

    it 'updates a plan' do
      result = plans_service.call

      updated_plan = result.plan
      aggregate_failures do
        expect(updated_plan.name).to eq('Updated plan name')
        expect(updated_plan.invoice_display_name).to eq(plan_invoice_display_name)
        expect(updated_plan.taxes.pluck(:code)).to eq([tax2.code])
        expect(plan.charges.count).to eq(2)
        expect(plan.charges.order(created_at: :asc).first.invoice_display_name).to eq('charge1')
        expect(plan.charges.order(created_at: :asc).second.invoice_display_name).to eq('charge2')
      end
    end

    context 'when charges are not passed' do
      let(:charge) { create(:standard_charge, plan:) }
      let(:update_args) do
        {
          name: plan_name,
          code: 'new_plan',
          interval: 'monthly',
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: 'EUR',
        }
      end

      before { charge }

      it 'does not sanitize charges' do
        result = plans_service.call

        updated_plan = result.plan
        aggregate_failures do
          expect(updated_plan.name).to eq('Updated plan name')
          expect(plan.charges.count).to eq(1)
        end
      end
    end

    context 'when plan is not found' do
      let(:applied_tax) { nil }
      let(:plan) { nil }

      it 'returns an error' do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('plan_not_found')
        end
      end
    end

    context 'with validation error' do
      let(:plan_name) { nil }

      it 'returns an error' do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end

      context 'with premium charge model' do
        let(:plan_name) { 'foo' }

        let(:charges_args) do
          [
            {
              billable_metric_id: sum_billable_metric.id,
              charge_model: 'graduated_percentage',
              pay_in_advance: true,
              invoiceable: false,
              properties: {
                graduated_percentage_ranges: [
                  {
                    from_value: 0,
                    to_value: 10,
                    rate: '3',
                    flat_amount: '0',
                  },
                  {
                    from_value: 11,
                    to_value: nil,
                    rate: '2',
                    flat_amount: '3',
                  },
                ],
              },
            },
          ]
        end

        it 'returns an error' do
          result = plans_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:charge_model]).to eq(['value_is_mandatory'])
          end
        end

        context 'when premium' do
          around { |test| lago_premium!(&test) }

          it 'saves premium charge model' do
            plans_service.call

            expect(plan.charges.graduated_percentage.first).to have_attributes(
              {
                pay_in_advance: true,
                invoiceable: false,
                charge_model: 'graduated_percentage',
              },
            )
          end
        end
      end
    end

    context 'with metrics from other organization' do
      let(:billable_metric) { create(:billable_metric) }

      it 'returns an error' do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('billable_metrics_not_found')
        end
      end
    end

    context 'with existing charges' do
      let!(:existing_charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: sum_billable_metric.id,
          amount_currency: 'USD',
          properties: {
            amount: '300',
          },
        )
      end

      let(:update_args) do
        {
          id: plan.id,
          name: plan_name,
          code: 'new_plan',
          interval: 'monthly',
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: 'EUR',
          charges: [
            {
              id: existing_charge.id,
              billable_metric_id: sum_billable_metric.id,
              charge_model: 'standard',
              pay_in_advance: true,
              prorated: true,
              invoiceable: false,
              group_properties: [
                {
                  group_id: group.id,
                  values: { amount: '100' },
                },
              ],
            },
            {
              billable_metric_id: billable_metric.id,
              charge_model: 'standard',
              min_amount_cents: 100,
              properties: {
                amount: '300',
              },
              tax_codes: [tax1.code],
            },
          ],
        }
      end

      it 'updates existing charge and creates an other one' do
        expect { plans_service.call }.to change(Charge, :count).by(1)

        charge = plan.charges.where(pay_in_advance: false).first
        expect(charge.taxes.pluck(:code)).to eq([tax1.code])
      end

      it 'updates existing charge' do
        expect { plans_service.call }
          .to change(GroupProperty, :count).by(1)

        expect(existing_charge.reload).to have_attributes(
          prorated: true,
          properties: { 'amount' => '0' },
        )
        expect(existing_charge.group_properties.first).to have_attributes(
          group_id: group.id,
          values: { 'amount' => '100' },
        )
      end

      it 'does not update premium attributes' do
        plan = plans_service.call.plan

        expect(existing_charge.reload).to have_attributes(pay_in_advance: true, invoiceable: true)
        expect(plan.charges.where(pay_in_advance: false).first.min_amount_cents).to eq(0)
      end

      context 'when premium' do
        around { |test| lago_premium!(&test) }

        it 'saves premium attributes' do
          plans_service.call

          expect(existing_charge.reload).to have_attributes(pay_in_advance: true, invoiceable: false)
          charge = plan.charges.where(pay_in_advance: false).first
          expect(charge.min_amount_cents).to eq(100)
        end
      end
    end

    context 'with existing charge attached to subscription' do
      let(:existing_charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: sum_billable_metric.id,
          amount_currency: 'USD',
          properties: {
            amount: '300',
          },
        )
      end

      let(:subscription) { create(:subscription, plan:) }

      let(:update_args) do
        {
          id: plan.id,
          code: 'new_plan',
          amount_cents: 200,
          charges: [
            {
              id: existing_charge.id,
              billable_metric_id: sum_billable_metric.id,
              charge_model: 'standard',
              tax_codes: [tax2.code],
            },
          ],
        }
      end

      before do
        existing_charge && subscription
      end

      it 'updates existing charge', :aggregate_failures do
        expect { plans_service.call }.not_to change(Charge, :count)
        expect(plan.charges.first.taxes.pluck(:code)).to eq([tax2.code])
      end
    end

    context 'with charge to delete' do
      let(:subscription) { create(:subscription, plan:) }
      let(:charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: billable_metric.id,
          properties: { amount: '300' },
        )
      end

      let(:update_args) do
        {
          id: plan.id,
          name: plan_name,
          code: 'new_plan',
          interval: 'monthly',
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: 'EUR',
          charges: [],
        }
      end

      let(:billable_metric) { sum_billable_metric }
      let(:group_property) { create(:group_property, group:, charge:) }
      let(:group) { create(:group, billable_metric:) }

      before do
        subscription
        charge
        group_property
      end

      it 'discards the charge' do
        freeze_time do
          expect { plans_service.call }
            .to change { charge.reload.deleted_at }.from(nil).to(Time.current)
        end
      end

      it 'discards group properties related to the charge' do
        freeze_time do
          expect { plans_service.call }
            .to change { group_property.reload.deleted_at }.from(nil).to(Time.current)
        end
      end

      it 'enqueues a Invoices::RefreshBatchJob' do
        invoice = create(:invoice, :draft)
        create(:invoice_subscription, subscription:, invoice:)

        expect do
          plans_service.call
        end.to have_enqueued_job(Invoices::RefreshBatchJob).with([invoice.id])
      end
    end

    context 'when attached to a subscription' do
      let(:existing_charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: sum_billable_metric.id,
          properties: {
            amount: '300',
          },
        )
      end

      let(:update_args) do
        {
          id: plan.id,
          name: plan_name,
          code: 'new_plan',
          interval: 'monthly',
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: 'EUR',
          charges: [
            {
              id: existing_charge.id,
              billable_metric_id: sum_billable_metric.id,
              charge_model: 'standard',
              properties: {
                amount: '100',
              },
            },
            {
              billable_metric_id: billable_metric.id,
              charge_model: 'standard',
              properties: {
                amount: '300',
              },
            },
          ],
        }
      end

      before do
        create(:subscription, plan:)
      end

      it 'updates only name description and new charges' do
        result = plans_service.call

        updated_plan = result.plan
        aggregate_failures do
          expect(updated_plan.name).to eq('Updated plan name')
          expect(plan.charges.count).to eq(2)
        end
      end
    end
  end
end
