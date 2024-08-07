# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsageThresholds::OverrideService, type: :service do
  subject(:override_service) { described_class.new(threshold:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe '#call' do
    let(:threshold) { create(:usage_threshold, plan:) }
    let(:plan) { create(:plan, organization:) }

    let(:params) do
      {
        id: threshold.id,
        plan_id: plan.id,
        threshold_display_name: 'Overriden threshold',
        amount_cents: 1000,
        amount_currency: 'JPY'
      }
    end

    before { threshold }

    it 'creates a threshold based on the given threshold', :aggregate_failures do
      expect { override_service.call }.to change(UsageThreshold, :count).by(1)

      threshold = UsageThreshold.order(:created_at).last

      expect(threshold).to have_attributes(
        amount_currency: 'JPY',
        recurring: threshold.recurring,
        # Overriden attributes
        plan_id: plan.id,
        threshold_display_name: 'Overriden threshold',
        amount_cents: 1000
      )
    end
  end
end
