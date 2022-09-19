# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetric, type: :model do
  subject(:billable_metric) { described_class.new }

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
end
