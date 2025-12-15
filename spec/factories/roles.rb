# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    name { Faker::Job.unique.title }
    custom

    trait :custom do
      organization { create(:organization) }
      permissions { %w[organization:view] }
    end

    trait :predefined do
      organization { nil }
      permissions { [] }
    end

    trait :admin do
      predefined
      name { "Admin" }
      admin { true }
    end

    trait :finance do
      predefined
      name { "Finance" }
    end

    trait :manager do
      predefined
      name { "Manager" }
    end

    to_create do |instance|
      existing = Role.unscoped.with_names(instance.name).with_organization(instance.organization&.id).first
      existing || instance.tap { |r| r.save(validate: false) }
    end
  end
end
