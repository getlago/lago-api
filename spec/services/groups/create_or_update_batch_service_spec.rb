# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Groups::CreateOrUpdateBatchService, type: :service do
  subject(:service) do
    described_class.call(billable_metric:, group_params:)
  end

  let(:billable_metric) { create(:billable_metric) }

  context 'when group params is empty' do
    let(:group_params) { {} }

    it 'does not create any groups' do
      expect { service }.not_to change(Group, :count)
    end
  end

  context 'when format is not valid' do
    it 'returns an error' do
      result = create_groups({key: 0, values: 1})
      expect(result.error.messages[:group]).to eq(['value_is_invalid'])

      result = create_groups({key: 'foo'})
      expect(result.error.messages[:group]).to eq(['value_is_invalid'])

      result = create_groups({invalid: 'foo', values: ['bar']})
      expect(result.error.messages[:group]).to eq(['value_is_invalid'])

      result = create_groups({key: 'foo', values: 'bar'})
      expect(result.error.messages[:group]).to eq(['value_is_invalid'])

      result = create_groups({key: 'foo', values: [1, 2]})
      expect(result.error.messages[:group]).to eq(['value_is_invalid'])

      result = create_groups({key: 'foo', values: [{name: 1}]})
      expect(result.error.messages[:group]).to eq(['value_is_invalid'])

      result = create_groups({key: 'foo', values: [{name: 'bar', key: 1, values: ['baz']}]})
      expect(result.error.messages[:group]).to eq(['value_is_invalid'])

      result = create_groups({key: 'foo', values: [{name: 'bar', key: 'baz', values: [1]}]})
      expect(result.error.messages[:group]).to eq(['value_is_invalid'])
    end

    def create_groups(group_params)
      described_class.call(billable_metric:, group_params:)
    end
  end

  context 'when three dimensions' do
    let(:group_params) do
      {
        key: 'region',
        values: [
          {
            name: 'Europe',
            key: 'cloud',
            values: [
              {
                name: 'AWS',
                key: 'country',
                values: %w[France]
              },
            ]
          },
        ]
      }
    end

    it 'returns an error' do
      result = service

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:group]).to eq(['value_is_invalid'])
      end
    end
  end

  context 'with one dimension' do
    let(:group_params) do
      {key: 'region', values: %w[usa europe usa]}
    end
    let(:group1) { create(:group, billable_metric:, key: 'region', value: 'europe', deleted_at: Time.current) }
    let(:group2) { create(:group, billable_metric:, key: 'region', value: 'africa') }

    before { group1 && group2 }

    it 'assigns expected groups' do
      expect { service }.to change(Group, :count).by(1)

      expect(billable_metric.groups.pluck(:key, :value))
        .to contain_exactly(%w[region usa], %w[region europe])
    end

    it 'marks invoices as ready to be refreshed' do
      invoice = create(:invoice, :draft)
      subscription = create(:subscription)
      create(:standard_charge, plan: subscription.plan, billable_metric:)
      create(:invoice_subscription, subscription:, invoice:)

      expect { service }.to change { invoice.reload.ready_to_be_refreshed }.to(true)
    end
  end

  context 'with two dimensions' do
    let(:group_params) do
      {
        key: 'cloud',
        values: [
          {
            name: 'AWS',
            invoice_display_name: "AWS Invoice name",
            key: 'region',
            values: %w[usa europe]
          },
          {
            name: 'Google',
            key: 'region',
            values: %w[usa usa]
          },
        ]
      }
    end

    let(:parent_group1) { create(:group, billable_metric:, key: 'cloud', value: 'AWS') }
    let(:parent_group2) { create(:group, billable_metric:, key: 'cloud', value: 'Microsoft') }
    let(:group1) { create(:group, billable_metric:, key: 'region', value: 'europe', parent_group_id: parent_group1.id) }
    let(:group2) { create(:group, billable_metric:, key: 'region', value: 'africa', parent_group_id: parent_group1.id) }
    let(:group3) { create(:group, billable_metric:, key: 'region', value: 'europe', parent_group_id: parent_group2.id) }

    before { group1 && group2 && group3 }

    it 'assigns expected groups' do
      expect { service }.not_to change { billable_metric.reload.groups.count }

      groups = billable_metric.reload.groups
      aws = groups.find_by(key: 'cloud', value: 'AWS')
      expect(aws.children).to include(group1)
      expect(aws.children.pluck(:key, :value)).to contain_exactly(%w[region usa], %w[region europe])

      google = groups.find_by(key: 'cloud', value: 'Google')
      expect(google.children.pluck(:key, :value)).to eq([%w[region usa]])
    end

    it 'marks invoices as ready to be refreshed' do
      invoice = create(:invoice, :draft)
      subscription = create(:subscription)
      create(:standard_charge, plan: subscription.plan, billable_metric:)
      create(:invoice_subscription, subscription:, invoice:)

      expect { service }.to change { invoice.reload.ready_to_be_refreshed }.to(true)
    end
  end
end
