# frozen_string_literal: true

require "rails_helper"

describe X402::SignInNonce do
  subject(:sign_in_nonce) { build(:x402_sign_in_nonce) }

  describe "associations" do
    it { expect(sign_in_nonce).to belong_to(:organization) }
  end

  describe "validations" do
    it do
      expect(sign_in_nonce).to validate_presence_of(:agent_address)
      expect(sign_in_nonce).to validate_presence_of(:nonce)
    end
  end

  describe "unique nonce index" do
    subject(:insert) { create(:x402_sign_in_nonce, organization:, agent_address:, nonce:) }

    let(:existing) { create(:x402_sign_in_nonce) }
    let(:organization) { existing.organization }
    let(:agent_address) { existing.agent_address }
    let(:nonce) { existing.nonce }

    it "refuses the same nonce for the same address" do
      expect { insert }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_sign_in_nonces_on_organization_address_nonce/)
    end

    context "with another address" do
      let(:agent_address) { X402::Network.checksum("0x#{SecureRandom.hex(20)}") }

      it { expect { insert }.not_to raise_error }
    end

    context "with another organization" do
      let(:organization) { create(:organization) }

      it { expect { insert }.not_to raise_error }
    end
  end
end
