# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::OverrideService, type: :service do
  subject(:override_service) { described_class.new(charge:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe '#call' do
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:group) { create(:group, billable_metric:) }
    let(:group2) { create(:group, billable_metric:) }
    let(:tax) { create(:tax, organization:) }

    let(:charge) do
      create(
        :standard_charge,
        billable_metric:,
        properties: { amount: '300' },
        group_properties: [
          build(
            :group_property,
            group:,
            values: { amount: '10', amount_currency: 'EUR' },
          ),
          build(
            :group_property,
            group: group2,
            values: { amount: '20', amount_currency: 'EUR' },
          ),
        ],
      )
    end

    let(:plan) { create(:plan, organization:) }
    let(:params) do
      {
        id: charge.id,
        plan_id: plan.id,
        # invoice_display_name: 'invoice display name',
        min_amount_cents: 1000,
        properties: { amount: '200' },
        tax_codes: [tax.code],
        group_properties: [
          {
            group_id: group.id,
            values: { amount: '100' },
          },
        ],
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

        expect(charge.group_properties.count).to eq(2)
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
          properties: { 'amount' => '200' },
        )
        expect(charge.group_properties.count).to eq(1)
        expect(charge.group_properties.with_discarded.discarded.count).to eq(1)
        expect(charge.group_properties.first).to have_attributes(
          {
            group_id: group.id,
            values: { 'amount' => '100' },
          },
        )
        expect(charge.taxes).to contain_exactly(tax)
      end
    end
  end
end
