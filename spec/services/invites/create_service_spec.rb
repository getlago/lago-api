# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invites::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe '#call' do
    let(:create_args) do
      {
        email: 'super@email.com',
        organization_id: organization.id,
      }
    end

    it 'creates an invite' do
      expect { create_service.call(**create_args) }
        .to change(Invite, :count).by(1)
    end

    context 'with validation error' do
      it 'returns an error' do
        result = create_service.call(organization_id: organization.id)

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end

    context 'with already existing invite' do
      it 'returns an error' do
        create(:invite, organization: organization, email: create_args[:email])
        result = create_service.call(**create_args)

        expect(result).not_to be_success
        expect(result.error_code).to eq('invite_already_exists')
      end
    end

    context 'with already existing member' do
      let(:user) { create(:user, email: 'super@email.com') }

      it 'returns an error' do
        create(:membership, organization: organization, user: user)

        result = create_service.call(**create_args)

        expect(result).not_to be_success
        expect(result.error_code).to eq('email_already_used')
      end
    end
  end
end
