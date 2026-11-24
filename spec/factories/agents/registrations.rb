# frozen_string_literal: true

FactoryBot.define do
  factory :agent_registration, class: "Agents::Registration" do
    storefront factory: :agent_storefront_integration
    organization { storefront.organization }
    public_key { Base64.urlsafe_encode64(SecureRandom.bytes(32), padding: false) }
    key_id { Agents::Auth::ChallengeService.key_id(Base64.urlsafe_decode64(public_key)) }
  end
end
