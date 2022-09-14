# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::ValidateService, type: :service do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization: organization) }

  let(:args) do
    {
      name: 'plan_name',
      organization_id: organization.id,
      overridden_plan_id: plan.id,
      code: 'new_plan',
      interval: 'monthly',
      pay_in_advance: false,
      amount_cents: 200,
      amount_currency: 'EUR',
    }
  end

  describe '.valid?' do
    it 'returns true' do
      expect(validate_service).to be_valid
    end

    context 'with invalid overridden_plan_id' do
      let(:other_organization) { create(:organization) }
      let(:plan) { create(:plan, organization: other_organization) }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error_details.first).to eq('overridden_plan_not_found')
      end
    end

    context 'with invalid charge number' do
      let(:standard_charge) { create(:standard_charge) }
      let(:plan) { create(:plan, organization: organization, charges: [standard_charge]) }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error_details.first).to eq('incorrect_charge_number')
      end
    end
  end
end
