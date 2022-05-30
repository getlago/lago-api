# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AddOns::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:create_args) do
      {
        name: 'Super Add-on',
        code: 'free-beer-for-us',
        description: 'This is description',
        organization_id: organization.id,
        amount_cents: 100,
        amount_currency: 'EUR'
      }
    end

    it 'creates an add-on' do
      expect { create_service.create(**create_args) }
        .to change(AddOn, :count).by(1)
    end

    context 'with validation error' do
      before do
        create(
          :add_on,
          organization: organization,
          code: 'free-beer-for-us',
        )
      end

      it 'returns an error' do
        result = create_service.create(**create_args)

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end
  end
end
