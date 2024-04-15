# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetric, type: :model do
  subject(:billable_metric) { create(:billable_metric) }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to have_many(:filters).dependent(:delete_all) }
  it { is_expected.to have_many(:netsuite_mappings).dependent(:destroy) }

  it { validate_presence_of(:field_name) }
  it { validate_presence_of(:custom_aggregator) }

  describe '#aggregation_type=' do
    let(:billable_metric) { described_class.new }

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

  describe '#validate_recurring' do
    let(:recurring) { false }
    let(:billable_metric) { build(:max_billable_metric, recurring:) }

    it 'does not return an error if recurring is false for max_agg' do
      expect(billable_metric).to be_valid
    end

    context 'when recurring is true' do
      let(:recurring) { true }

      it 'returns an error for max_agg' do
        aggregate_failures do
          expect(billable_metric).not_to be_valid
          expect(billable_metric.errors.messages[:recurring]).to include('not_compatible_with_aggregation_type')
        end
      end
    end

    context 'when recurring is true and aggregation type is latest_agg' do
      let(:billable_metric) { build(:latest_billable_metric, recurring:) }
      let(:recurring) { true }

      it 'returns an error' do
        aggregate_failures do
          expect(billable_metric).not_to be_valid
          expect(billable_metric.errors.messages[:recurring]).to include('not_compatible_with_aggregation_type')
        end
      end
    end
  end

  describe '#selectable_groups' do
    context 'without active groups' do
      it 'returns an empty collection' do
        expect(billable_metric.selectable_groups).to be_empty
      end
    end

    context 'when groups contain one dimension' do
      it 'returns all groups' do
        one = create(:group, billable_metric:, key: 'country', value: 'france')
        second = create(:group, billable_metric:, key: 'country', value: 'italy')

        expect(billable_metric.selectable_groups).to contain_exactly(one, second)
      end
    end

    context 'when groups contain two dimensions' do
      it 'returns only children groups' do
        france = create(:group, billable_metric:, key: 'country', value: 'france')
        italy = create(:group, billable_metric:, key: 'country', value: 'italy')
        one = create(:group, billable_metric:, key: 'cloud', value: 'aws', parent_group_id: france.id)
        second = create(:group, billable_metric:, key: 'cloud', value: 'google', parent_group_id: france.id)
        third = create(:group, billable_metric:, key: 'cloud', value: 'google', parent_group_id: italy.id)

        expect(billable_metric.selectable_groups).to contain_exactly(one, second, third)
      end
    end

    context 'when billable metric and group are deleted' do
      it 'returns all groups' do
        billable_metric.discard!
        one = create(:group, :deleted, billable_metric:, key: 'country', value: 'france')
        second = create(:group, :deleted, billable_metric:, key: 'country', value: 'italy')

        expect(billable_metric.selectable_groups).to contain_exactly(one, second)
      end
    end
  end

  describe '#active_groups_as_tree' do
    context 'without active groups' do
      it 'returns {}' do
        expect(billable_metric.active_groups_as_tree).to eq({})
      end
    end

    context 'when groups contain one dimension' do
      before do
        create(:group, billable_metric:, key: 'country', value: 'france')
        create(:group, billable_metric:, key: 'country', value: 'italy')
      end

      it 'returns a tree with one dimension' do
        expect(billable_metric.active_groups_as_tree).to eq(
          {
            key: 'country',
            values: %w[france italy],
          },
        )
      end
    end

    context 'when groups contain two dimensions' do
      before do
        france = create(:group, billable_metric:, key: 'country', value: 'france')
        italy = create(:group, billable_metric:, key: 'country', value: 'italy')
        create(:group, billable_metric:, key: 'cloud', value: 'aws', parent_group_id: france.id)
        create(:group, billable_metric:, key: 'cloud', value: 'google', parent_group_id: france.id)
        create(:group, billable_metric:, key: 'cloud', value: 'google', parent_group_id: italy.id)
      end

      it 'returns a tree with two dimensions' do
        expect(billable_metric.active_groups_as_tree).to eq(
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
