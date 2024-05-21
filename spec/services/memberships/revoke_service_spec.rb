# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Memberships::RevokeService, type: :service do
  subject(:revoke_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }

  describe '#call' do
    context 'when revoking my own membership' do
      it 'returns an error' do
        result = revoke_service.call(membership.id)

        expect(result).not_to be_success
        expect(result.error.code).to eq('cannot_revoke_own_membership')
      end
    end

    context 'when membership is not found' do
      it 'returns an error' do
        result = revoke_service.call(nil)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('membership_not_found')
      end
    end

    context 'when revoking another membership' do
      let(:another_membership) { create(:membership, organization: membership.organization) }

      it 'revokes the membership' do
        freeze_time do
          result = revoke_service.call(another_membership.id)

          expect(result).to be_success
          expect(result.membership.id).to eq(another_membership.id)
          expect(result.membership.status).to eq('revoked')
          expect(result.membership.revoked_at).to eq(Time.current)
        end
      end
    end

    context 'when removing the last admin' do
      let(:membership) { create(:membership, role: :finance) }
      let(:admin_membership) { create(:membership, organization: membership.organization, role: :admin) }

      it 'returns an error' do
        result = revoke_service.call(admin_membership.id)

        expect(result).not_to be_success
        expect(result.error.code).to eq('last_admin')
      end
    end
  end
end
