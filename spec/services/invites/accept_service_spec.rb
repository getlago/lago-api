# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invites::AcceptService, type: :service do
  subject(:accept_service) { described_class.new }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:user) { create(:user) }
  let(:invite) { create(:invite, organization:, email: user.email) }
  let(:accept_args) do
    {
      email: invite.email,
      password: 'ILoveLago!',
      token: invite.token,
    }
  end

  describe '#call' do
    it 'sets the recipient of the invite' do
      expect { accept_service.call(**accept_args) }
        .to change { invite.reload.membership_id }.from(nil)
    end

    it 'marks the invite as accepted' do
      freeze_time do
        expect { accept_service.call(**accept_args) }
          .to change { invite.reload.status }.from('pending').to('accepted')
          .and change(invite, :accepted_at).from(nil).to(Time.current)
      end
    end

    it 'sets user, membership and organization' do
      result = accept_service.call(**accept_args)

      expect(result.user).to be_present
      expect(result.membership).to be_present
      expect(result.organization).to be_present
      expect(result.token).to be_present
    end

    context 'when user have already been invited then revoked' do
      let(:revoked_membership) { create(:membership, :revoked, organization:) }
      let(:accepted_invite) do
        create(:invite, organization:, email: revoked_membership.user.email, status: :accepted)
      end
      let(:new_invite) { create(:invite, organization:, email: revoked_membership.user.email) }

      it 'sets user, membership and organization' do
        result = accept_service.call(
          email: revoked_membership.user.email,
          password: accept_args[:password],
          token: new_invite[:token],
        )

        expect(result).to be_success
        expect(result.user).to be_present
        expect(result.membership).to be_present
        expect(result.organization).to be_present
        expect(result.token).to be_present
      end
    end

    context 'when invite is already accepted' do
      let(:accepted_invite) { create(:invite, organization:, status: :accepted) }

      it 'returns invite_not_found error' do
        result = accept_service.call(
          email: accepted_invite[:email],
          password: accept_args[:password],
          token: accepted_invite[:token],
        )

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq('invite_not_found')
      end
    end

    context 'when invite is revoked' do
      let(:revoked_invite) { create(:invite, organization:, status: :revoked) }

      it 'returns invite_not_found error' do
        result = accept_service.call(
          email: revoked_invite[:email],
          password: accept_args[:password],
          token: revoked_invite[:token],
        )

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq('invite_not_found')
      end
    end

    context 'without email' do
      it 'returns an error' do
        result = accept_service.call(email: nil, password: accept_args[:password], token: accept_args[:token])

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:email]).to eq(['value_is_mandatory'])
      end
    end

    context 'without password' do
      it 'returns an error' do
        result = accept_service.call(email: accept_args[:email], password: nil, token: accept_args[:token])

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:password]).to eq(['value_is_mandatory'])
      end

      context 'without token' do
        it 'returns invite_not_found error' do
          result = accept_service.call(email: accept_args[:email], password: accept_args[:password], token: nil)

          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('invite_not_found')
        end
      end
    end
  end
end
