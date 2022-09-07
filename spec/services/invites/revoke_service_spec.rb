# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invites::RevokeService, type: :service do
  subject(:revoke_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:invite) { create(:invite) }

  describe '#call' do
    context 'when invite is not found' do
      it 'returns an error' do
        result = revoke_service.call(nil)

        expect(result).not_to be_success
        expect(result.error).to eq('invite_not_found')
      end
    end

    context 'when revoking invite' do
      let(:another_invite) { create(:invite) }

      it 'revokes the invite' do
        freeze_time do
          result = revoke_service.call(another_invite.id)

          expect(result).to be_success
          expect(result.invite.id).to eq(another_invite.id)
          expect(result.invite).to be_revoked
          expect(result.invite.revoked_at).to eq(Time.current)
        end
      end
    end
  end
end
