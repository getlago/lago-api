# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::DestroyService, type: :service do
  subject(:plans_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'destroy' do
    let(:plan) { create(:plan, organization: organization) }

    it 'destroys the plan' do
      id = plan.id

      expect { plans_service.destroy(id) }
        .to change(Plan, :count).by(-1)
    end

    context 'when plan is not found' do
      it 'returns an error' do
        result = plans_service.destroy(nil)

        expect(result).not_to be_success
        expect(result.error).to eq('not_found')
      end
    end

    context 'when plan is attached to subscription' do
      before do
        create(:subscription, plan: plan)
      end

      it 'returns an error' do
        result = plans_service.destroy(plan.id)

        expect(result).not_to be_success
        expect(result.error_code).to eq('forbidden')
      end
    end
  end

  describe 'destroy_from_api' do
    let(:plan) { create(:plan, organization: organization) }

    it 'destroys the plan' do
      code = plan.code

      expect { plans_service.destroy_from_api(organization: organization, code: code) }
        .to change(Plan, :count).by(-1)
    end

    context 'when plan is not found' do
      it 'returns an error' do
        result = plans_service.destroy_from_api(organization: organization, code: 'invalid12345')

        expect(result).not_to be_success
        expect(result.error_code).to eq('not_found')
      end
    end

    context 'when plan is attached to subscription' do
      let(:subscription) { create(:subscription, plan: plan) }

      before { subscription }

      it 'returns an error' do
        result = plans_service.destroy_from_api(organization: organization, code: plan.code)

        expect(result).not_to be_success
        expect(result.error_code).to eq('forbidden')
      end
    end
  end
end
