# frozen_string_literal: true

FactoryBot.define do
  factory :entitlement, class: "Entitlement::Entitlement" do
    organization { feature&.organization || plan&.organization || association(:organization) }
    association :feature, factory: :feature
    association :plan
  end
end
