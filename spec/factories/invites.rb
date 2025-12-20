# frozen_string_literal: true

FactoryBot.define do
  factory :invite do
    organization

    status { "pending" }
    email { Faker::Internet.email }
    token { SecureRandom.hex(20) }
    roles { %w[admin] }

    after(:build) do |invite|
      names = Role.with_names(*invite.roles).with_organization(invite.organization.id).pluck(:name)
      missed_names = invite.roles.map(&:downcase) - names.map(&:downcase)
      missed_names.each { |name| create(:role, name.to_sym) }
    end
  end
end
