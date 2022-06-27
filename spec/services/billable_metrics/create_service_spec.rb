# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:create_args) do
      {
        name: 'New Metric',
        code: 'new_metric',
        description: 'New metric description',
        organization_id: organization.id,
        aggregation_type: 'count_agg'
      }
    end

    it 'creates a billable metric' do
      expect { create_service.create(**create_args) }
        .to change { BillableMetric.count }.by(1)
    end

    context 'with validation error' do
      before do
        create(
          :billable_metric,
          code: create_args[:code],
          organization: membership.organization
        )
      end

      it 'returns an error' do
        result = create_service.create(**create_args)

        expect(result).to_not be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end
  end
end
