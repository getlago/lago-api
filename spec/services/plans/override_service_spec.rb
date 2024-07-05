# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::OverrideService, type: :service do
  subject(:override_service) { described_class.new(plan: parent_plan, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe '#call' do
    let(:parent_plan) { create(:plan, organization:) }
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:) }
    let(:tax) { create(:tax, organization:) }

    let(:charge) do
      create(
        :standard_charge,
        plan: parent_plan,
        billable_metric:,
        properties: {amount: '300'}
      )
    end

    let(:filter) do
      create(
        :charge_filter,
        charge:,
        properties: {amount: '10'}
      )
    end

    let(:filter_value) do
      create(
        :charge_filter_value,
        charge_filter: filter,
        billable_metric_filter:,
        values: [billable_metric_filter.values.first]
      )
    end

    let(:params) do
      {
        amount_cents: 300,
        amount_currency: 'USD',
        invoice_display_name: 'invoice display name',
        name: 'overridden name',
        description: 'overridden description',
        trial_period: 20,
        tax_codes: [tax.code],
        charges: charges_params,
        minimum_commitment: minimum_commitment_params
      }
    end

    let(:minimum_commitment_params) do
      {
        amount_cents: minimum_commitment_amount_cents,
        invoice_display_name: minimum_commitment_invoice_display_name,
        tax_codes: [tax.code]
      }
    end

    let(:minimum_commitment_invoice_display_name) { 'Minimum spending' }
    let(:minimum_commitment_amount_cents) { 100 }

    let(:charges_params) do
      [
        {
          id: charge.id,
          min_amount_cents: 1000
        }
      ]
    end

    around { |test| lago_premium!(&test) }

    before do
      charge
      allow(SegmentTrackJob).to receive(:perform_later)
      filter_value
    end

    it 'creates a plan based from the parent plan', :aggregate_failures do
      expect { override_service.call }.to change(Plan, :count).by(1)

      plan = Plan.order(:created_at).last
      expect(plan).to have_attributes(
        organization_id: organization.id,
        bill_charges_monthly: parent_plan.bill_charges_monthly,
        code: parent_plan.code,
        interval: parent_plan.interval,
        pay_in_advance: parent_plan.pay_in_advance,
        # Parent id
        parent_id: parent_plan.id,
        # Overriden attributes
        amount_cents: 300,
        amount_currency: 'USD',
        description: 'overridden description',
        invoice_display_name: 'invoice display name',
        name: 'overridden name',
        trial_period: 20
      )

      expect(plan.taxes).to contain_exactly(tax)

      expect(plan.minimum_commitment).to have_attributes(
        commitment_type: 'minimum_commitment',
        amount_cents: minimum_commitment_amount_cents,
        invoice_display_name: minimum_commitment_invoice_display_name
      )

      expect(plan.minimum_commitment.taxes.first).to eq(tax)
    end

    it 'calls SegmentTrackJob' do
      plan = override_service.call.plan

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
          nb_charges: 1,
          nb_standard_charges: 1,
          nb_percentage_charges: 0,
          nb_graduated_charges: 0,
          nb_package_charges: 0,
          organization_id: plan.organization_id,
          parent_id: plan.parent.id
        }
      )
    end

    it 'creates charges based from the parent plan', :aggregate_failures do
      charge2 = create(
        :graduated_charge,
        plan: parent_plan,
        billable_metric:,
        properties: {
          graduated_ranges: [
            {
              from_value: 0,
              to_value: nil,
              per_unit_amount: '0.01',
              flat_amount: '0.01'
            }
          ]
        }
      )

      expect { override_service.call }.to change(Plan, :count).by(1)

      plan = Plan.order(:created_at).last
      expect(plan.charges.count).to eq(2)

      graduated = plan.charges.graduated.first
      expect(graduated).to have_attributes(
        plan_id: plan.id,
        min_amount_cents: charge2.min_amount_cents,
        properties: charge2.properties
      )

      standard = plan.charges.standard.first
      expect(standard).to have_attributes(
        amount_currency: charge.amount_currency,
        billable_metric_id: billable_metric.id,
        charge_model: charge.charge_model,
        invoiceable: charge.invoiceable,
        pay_in_advance: charge.pay_in_advance,
        prorated: charge.prorated,
        properties: charge.properties,
        # Overriden attributes
        plan_id: plan.id,
        min_amount_cents: 1000
      )
    end

    context 'when minimum commitment is not valid' do
      let(:minimum_commitment_amount_cents) { nil }

      it 'returns error', :aggregate_failures do
        expect { override_service.call }.not_to change(Plan, :count)
        expect(override_service.call).not_to be_success
      end
    end
  end
end
