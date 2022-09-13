# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AddOns::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:add_on) { create(:add_on, organization: organization) }

  describe 'destroy' do
    before { add_on }

    it 'destroys the add-on' do
      expect { destroy_service.destroy(add_on.id) }
        .to change(AddOn, :count).by(-1)
    end

    context 'when add-on is not found' do
      it 'returns an error' do
        result = destroy_service.destroy(nil)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('add_on_not_found')
      end
    end
  end

  describe 'destroy_from_api' do
    let(:add_on) { create(:add_on, organization: organization) }

    it 'destroys the add_on' do
      code = add_on.code

      expect { destroy_service.destroy_from_api(organization: organization, code: code) }
        .to change(AddOn, :count).by(-1)
    end

    context 'when add-on is not found' do
      it 'returns an error' do
        result = destroy_service.destroy_from_api(organization: organization, code: 'invalid12345')

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('add_on_not_found')
      end
    end
  end
end
