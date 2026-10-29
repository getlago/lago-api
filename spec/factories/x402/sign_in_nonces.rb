# frozen_string_literal: true

FactoryBot.define do
  factory :x402_sign_in_nonce, class: "X402::SignInNonce" do
    organization
    agent_address { X402::Network.checksum("0x#{SecureRandom.hex(20)}") }
    nonce { SecureRandom.alphanumeric(32) }
  end
end
