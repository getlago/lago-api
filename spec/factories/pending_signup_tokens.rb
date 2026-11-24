# frozen_string_literal: true

FactoryBot.define do
  factory :pending_signup_token do
    transient do
      token { PendingSignupToken.generate }
    end

    pending_signup
    token_digest { PendingSignupToken.digest(token) }
    expires_at { PendingSignupToken::TTL.from_now }

    trait :expired do
      expires_at { 1.second.ago }
    end

    trait :replaced do
      status { "replaced" }
    end

    trait :consumed do
      status { "consumed" }
      consumed_at { Time.current }
    end

    trait :locked do
      failed_password_attempts { 5 }
    end
  end
end
