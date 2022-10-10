# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetric, type: :model do
  let(:billable_metric) { described_class.new }

  describe '#aggregation_type=' do
    it 'assigns the aggregation type' do
      billable_metric.aggregation_type = :count_agg
      billable_metric.valid?

      aggregate_failures do
        expect(billable_metric).to be_count_agg
        expect(billable_metric.errors[:aggregation_type]).to be_blank
      end
    end

    context 'when aggregation type is invalid' do
      it 'does not assign the aggregation type' do
        billable_metric.aggregation_type = :invalid_agg
        billable_metric.valid?

        aggregate_failures do
          expect(billable_metric.aggregation_type).to be_nil
          expect(billable_metric.errors[:aggregation_type]).to include('value_is_invalid')
        end
      end
    end
  end

  describe '#groups_as_tree' do
    let(:billable_metric) { create(:billable_metric) }

    context 'without active groups' do
      it 'returns {}' do
        expect(billable_metric.groups_as_tree).to eq({})
      end
    end

    context 'when groups contain one dimension' do
      before do
        create(:group, billable_metric: billable_metric, key: 'country', value: 'france')
        create(:group, billable_metric: billable_metric, key: 'country', value: 'italy')
      end

      it 'returns a tree with one dimension' do
        expect(billable_metric.groups_as_tree).to eq(
          {
            key: 'country',
            values: %w[france italy],
          },
        )
      end
    end

    context 'when groups contain two dimensions' do
      before do
        france = create(:group, billable_metric: billable_metric, key: 'country', value: 'france')
        italy = create(:group, billable_metric: billable_metric, key: 'country', value: 'italy')
        create(:group, billable_metric: billable_metric, key: 'cloud', value: 'aws', parent_group_id: france.id)
        create(:group, billable_metric: billable_metric, key: 'cloud', value: 'google', parent_group_id: france.id)
        create(:group, billable_metric: billable_metric, key: 'cloud', value: 'google', parent_group_id: italy.id)
      end

      it 'returns a tree with two dimensions' do
        expect(billable_metric.groups_as_tree).to eq(
          {
            key: 'country',
            values: [
              {
                name: 'france',
                key: 'cloud',
                values: %w[aws google],
              },
              {
                name: 'italy',
                key: 'cloud',
                values: %w[google],
              },
            ],
          },
        )
      end
    end
  end
end
