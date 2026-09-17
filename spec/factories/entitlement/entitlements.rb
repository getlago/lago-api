# frozen_string_literal: true

FactoryBot.define do
  factory :entitlement, class: "Entitlement::Entitlement" do
    organization { feature&.organization || plan&.organization || association(:organization) }
    association :feature, factory: :feature
    association :plan

    trait :subscription do
      plan { nil }
      association :subscription
    end

    trait :catalog_plan do
      plan { nil }
      association :catalog_plan
    end
  end
end
