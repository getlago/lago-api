# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetricsService, type: :service do
  subject { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:create_args) do
      {
        name: 'New Metric',
        code: 'new_metric',
        description: 'New metric description',
        organization_id: organization.id,
        aggregation_type: 'count_agg',
        billable_period: 'recurring',
        pro_rata: false,
        properties: {}
      }
    end

    it 'creates a billable metric' do
      expect { subject.create(**create_args) }
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
        expect { subject.create(**create_args) }
          .to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context 'when user is not member of the organization' do
      let(:organization) { create(:organization) }

      it 'returns an error' do
        result = subject.create(**create_args)

        expect(result.success?).to be_falsey
        expect(result.error).to eq('not_organization_member')
      end
    end
  end
end
