# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsersService, type: :service do
  subject(:user_service) { described_class.new }

  describe 'register' do
    it 'calls SegmentIdentifyJob' do
      allow(SegmentIdentifyJob).to receive(:perform_later)
      result = user_service.register('email', 'password', 'organization_name')

      expect(SegmentIdentifyJob).to have_received(:perform_later).with(
        membership_id: "membership/#{result.membership.id}",
      )
    end

    it 'calls SegmentTrackJob' do
      allow(SegmentTrackJob).to receive(:perform_later)
      result = user_service.register('email', 'password', 'organization_name')

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: "membership/#{result.membership.id}",
        event: 'organization_registered',
        properties: {
          organization_name: result.organization.name,
          organization_id: result.organization.id,
        },
      )
    end

    it 'creates an organization, user and membership' do
      result = user_service.register('email', 'password', 'organization_name')
      expect(result.user).to be_present
      expect(result.membership).to be_present
      expect(result.organization).to be_present
      expect(result.token).to be_present

      org = Organization.find(result.organization.id)
      expect(org.document_number_prefix).to eq("#{org.name.first(3).upcase}-#{org.id.last(4).upcase}")
    end

    context 'when user already exists' do
      let(:user) { create(:user) }

      it 'fails' do
        result = user_service.register(user.email, 'password', 'organization_name')

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:email)
          expect(result.error.messages[:email]).to include('user_already_exists')
        end
      end
    end

    context 'when signup is disabled' do
      before do
        ENV['LAGO_SIGNUP_DISABLED'] = 'true'
      end

      after do
        ENV['LAGO_SIGNUP_DISABLED'] = nil
      end

      it 'returns a not allowed error' do
        result = user_service.register('email', 'password', 'organization_name')

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.message).to eq('signup is disabled')
        end
      end
    end
  end

  describe 'register_from_invite' do
    it 'creates an organization, user and membership' do
      result = user_service.register('email', 'password', 'organization_name')
      expect(result.user).to be_present
      expect(result.membership).to be_present
      expect(result.organization).to be_present
      expect(result.token).to be_present
    end
  end

  describe 'login' do
    let(:membership) { create(:membership) }

    it 'calls SegmentIdentifyJob' do
      allow(SegmentIdentifyJob).to receive(:perform_later)
      result = user_service.login(membership.user.email, membership.user.password)

      expect(SegmentIdentifyJob).to have_received(:perform_later).with(
        membership_id: "membership/#{result.user.memberships.first.id}",
      )
    end
  end

  describe 'new_token' do
    let(:user) { create(:user) }

    it 'generates a jwt token for the user' do
      result = user_service.new_token(user)

      expect(result).to be_success
      expect(result.user).to eq(user)
      expect(result.token).to be_present
    end
  end
end
