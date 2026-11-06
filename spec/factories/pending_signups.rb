# frozen_string_literal: true

FactoryBot.define do
  factory :pending_signup do
    transient do
      password { "Lago-Passw0rd" }
      signup_secret { PendingSignup.generate_signup_secret }
    end

    sequence(:email) { |n| "jane#{n}@getlago.com" }
    normalized_email { PendingSignup.normalize_email(email) }
    mailbox_key { PendingSignup.mailbox_key(email) }
    password_digest { PendingSignup.digest_password(password) }
    signup_secret_digest { PendingSignup.digest_signup_secret(signup_secret) }
    expires_at { PendingSignup::RESEND_WINDOW.from_now }
    emails_sent_at { [Time.current] }

    trait :verified do
      user
      verified_at { Time.current }
    end

    trait :closed do
      closed_at { Time.current }

      after(:create) { |pending_signup| pending_signup.update!(password_digest: nil) }
    end

    trait :exhausted do
      emails_sent_at { Array.new(PendingSignup::MAX_EMAILS_PER_ATTEMPT) { Time.current } }
    end
  end
end
