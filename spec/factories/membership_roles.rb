# frozen_string_literal: true

FactoryBot.define do
  factory :membership_role do
    membership
    organization { membership.organization }
    role { association :role, organization: }
  end
end
