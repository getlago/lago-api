# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::CreateService, type: :service do
  subject(:plans_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:plan_name) { 'Some plan name' }
    let(:plan_invoice_display_name) { 'Some plan invoice name' }
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:sum_billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
    let(:billable_metric_filter) do
      create(:billable_metric_filter, billable_metric:, key: 'payment_method', values: %w[card physical])
    end
    let(:plan_tax) { create(:tax, organization:) }
    let(:charge_tax) { create(:tax, organization:) }
    let(:create_args) do
      {
        name: plan_name,
        invoice_display_name: plan_invoice_display_name,
        organization_id: organization.id,
        code: 'new_plan',
        interval: 'monthly',
        pay_in_advance: false,
        amount_cents: 200,
        amount_currency: 'EUR',
        tax_codes: [plan_tax.code],
        charges: charges_args,
        minimum_commitment: minimum_commitment_args
      }
    end

    let(:minimum_commitment_args) do
      {
        amount_cents: minimum_commitment_amount_cents,
        invoice_display_name: minimum_commitment_invoice_display_name,
        tax_codes: [plan_tax.code]
      }
    end

    let(:minimum_commitment_invoice_display_name) { 'Minimum spending' }
    let(:minimum_commitment_amount_cents) { 100 }

    let(:charges_args) do
      [
        {
          billable_metric_id: billable_metric.id,
          charge_model: 'standard',
          min_amount_cents: 100,
          tax_codes: [charge_tax.code],
          filters: [
            {
              values: {billable_metric_filter.key => ['card']},
              invoice_display_name: 'Card filter',
              properties: {amount: '90'}
            }
          ]
        },
        {
          billable_metric_id: sum_billable_metric.id,
          charge_model: 'graduated',
          pay_in_advance: true,
          invoiceable: false,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: 10,
                per_unit_amount: '2',
                flat_amount: '0'
              },
              {
                from_value: 11,
                to_value: nil,
                per_unit_amount: '3',
                flat_amount: '3'
              }
            ]
          }
        }
      ]
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a plan' do
      expect { plans_service.create(**create_args) }
        .to change(Plan, :count).by(1)

      plan = Plan.order(:created_at).last
      expect(plan.taxes.pluck(:code)).to eq([plan_tax.code])
      expect(plan.invoice_display_name).to eq(plan_invoice_display_name)
    end

    it 'does not create minimum commitment' do
      plans_service.create(**create_args)

      plan = Plan.order(:created_at).last

      expect(plan.minimum_commitment).to be_nil
    end

    it 'creates charges' do
      plans_service.create(**create_args)

      plan = Plan.order(:created_at).last
      expect(plan.charges.count).to eq(2)

      standard_charge = plan.charges.standard.first
      graduated_charge = plan.charges.graduated.first

      expect(standard_charge).to have_attributes(
        pay_in_advance: false,
        prorated: false,
        min_amount_cents: 0,
        invoiceable: true,
        properties: {'amount' => '0'}
      )
      expect(standard_charge.taxes.pluck(:code)).to eq([charge_tax.code])
      expect(standard_charge.filters.first).to have_attributes(
        invoice_display_name: 'Card filter',
        properties: {'amount' => '90'}
      )
      expect(standard_charge.filters.first.values.first).to have_attributes(
        billable_metric_filter_id: billable_metric_filter.id,
        values: ['card']
      )

      expect(graduated_charge).to have_attributes(pay_in_advance: true, invoiceable: true, prorated: false)
    end

    it 'calls SegmentTrackJob' do
      plan = plans_service.create(**create_args).plan

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'plan_created',
        properties: {
          code: plan.code,
          name: plan.name,
          invoice_display_name: plan.invoice_display_name,
          description: plan.description,
          plan_interval: plan.interval,
          plan_amount_cents: plan.amount_cents,
          plan_period: 'arrears',
          trial: plan.trial_period,
          nb_charges: 2,
          nb_standard_charges: 1,
          nb_percentage_charges: 0,
          nb_graduated_charges: 1,
          nb_package_charges: 0,
          organization_id: plan.organization_id,
          parent_id: nil
        }
      )
    end

    context 'when premium' do
      around { |test| lago_premium!(&test) }

      let(:charges_args) do
        [
          {
            billable_metric_id: billable_metric.id,
            charge_model: 'standard',
            min_amount_cents: 100,
            tax_codes: [charge_tax.code]
          },
          {
            billable_metric_id: sum_billable_metric.id,
            charge_model: 'graduated_percentage',
            pay_in_advance: true,
            invoiceable: false,
            regroup_paid_fees: 'invoice',
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
        ]
      end

      it 'saves premium attributes' do
        plan = plans_service.create(**create_args).plan

        expect(plan.minimum_commitment).to have_attributes(
          {
            amount_cents: minimum_commitment_amount_cents,
            invoice_display_name: minimum_commitment_invoice_display_name
          }
        )

        expect(plan.charges.standard.first).to have_attributes(
          {
            pay_in_advance: false,
            min_amount_cents: 100,
            invoiceable: true
          }
        )

        expect(plan.charges.graduated_percentage.first).to have_attributes(
          {
            pay_in_advance: true,
            invoiceable: false,
            regroup_paid_fees: 'invoice',
            charge_model: 'graduated_percentage'
          }
        )
      end
    end

    context 'with code already used by a deleted plan' do
      it 'creates a plan with the same code' do
        create(:plan, organization:, code: 'new_plan', deleted_at: Time.current)

        expect { plans_service.create(**create_args) }.to change(Plan, :count).by(1)

        plans = organization.plans.with_discarded
        expect(plans.count).to eq(2)
        expect(plans.pluck(:code).uniq).to eq(['new_plan'])
      end
    end

    context 'with validation error' do
      let(:plan_name) { nil }

      it 'returns an error' do
        result = plans_service.create(**create_args)

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
                graduated_ranges: [
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
          ]
        end

        it 'returns an error' do
          result = plans_service.create(**create_args)

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:charge_model]).to eq(['value_is_mandatory'])
          end
        end
      end
    end

    context 'with metrics from other organization' do
      let(:billable_metric) { create(:billable_metric) }

      it 'returns an error' do
        result = plans_service.create(**create_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('billable_metrics_not_found')
      end
    end
  end
end
