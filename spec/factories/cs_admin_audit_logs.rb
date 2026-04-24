# frozen_string_literal: true

FactoryBot.define do
  factory :cs_admin_audit_log do
    association :actor_user, factory: :user
    actor_email { actor_user.email }
    action { :toggle_on }
    association :organization
    feature_type { :premium_integration }
    feature_key { "netsuite" }
    before_value { false }
    after_value { true }
    reason { "Enabling for customer onboarding POC" }
  end
end
