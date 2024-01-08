# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GroupProperties::CreateOrUpdateBatchService, type: :service do
  subject(:service) do
    described_class.call(charge:, properties_params:)
  end

  let(:charge) { create(:standard_charge) }

  context 'when group properties params is empty' do
    let(:properties_params) { {} }

    it 'does not create any group properties' do
      expect { service }.not_to change(GroupProperty, :count)
    end
  end

  context 'when group properties are already assigned' do
    let(:group1) { create(:group, billable_metric: charge.billable_metric) }
    let(:group2) { create(:group, billable_metric: charge.billable_metric) }
    let(:group_property1) { create(:group_property, group: group1, charge:) }
    let(:group_property2) { create(:group_property, group: group2, charge:) }
    let(:properties_params) do
      [{ group_id: group1.id, invoice_display_name: 'Invoice Name', values: { amount: '1' } }]
    end

    before { group_property1 && group_property2 }

    it 'assigns expected group properties' do
      aggregate_failures do
        expect { service }.to change(GroupProperty, :count).by(-1)
        expect(group_property2.reload).to be_discarded
        expect(group_property1.reload.values).to eq({ 'amount' => '1' })
        expect(group_property1.reload.invoice_display_name).to eq('Invoice Name')
        expect(charge.reload.group_properties).to eq([group_property1])
      end
    end

    it 'marks invoices as ready to be refreshed' do
      invoice = create(:invoice, :draft)
      subscription = create(:subscription)
      charge = create(:standard_charge, plan: subscription.plan)
      create(:invoice_subscription, subscription:, invoice:)

      expect do
        described_class.call(charge:, properties_params:)
      end.to change { invoice.reload.ready_to_be_refreshed }.to(true)
    end
  end
end
