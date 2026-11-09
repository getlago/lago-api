# frozen_string_literal: true

FactoryBot.define do
  factory :agent_claim, class: "Agents::Claim" do
    registration factory: :agent_registration
    organization { registration.organization }

    transient do
      code { Agents::Claim.generate_code }
    end

    code_hash { Agents::Claim.digest(code) }

    trait :started do
      status { "started" }
      email { "owner@example.com" }
    end

    trait :verified do
      status { "verified" }
      verified_at { Time.current }
    end
  end
end
