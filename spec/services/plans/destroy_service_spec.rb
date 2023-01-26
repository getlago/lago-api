# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::DestroyService, type: :service do
  subject(:plans_service) { described_class.new(plan:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:plan) { create(:plan, organization:) }

  before { plan }

  describe '#call' do
    it 'destroys the plan' do
      expect { plans_service.call }
        .to change(Plan, :count).by(-1)
    end

    context 'when plan is not found' do
      let(:plan) { nil }

      it 'returns an error' do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('plan_not_found')
        end
      end
    end
  end
end
