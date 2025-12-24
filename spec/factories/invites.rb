# frozen_string_literal: true

FactoryBot.define do
  factory :invite do
    organization

    status { "pending" }
    email { Faker::Internet.email }
    token { SecureRandom.hex(20) }
    roles { %w[admin] }

    after(:build) do |invite|
      existing_names = Role.with_names(*invite.roles).with_organization(invite.organization.id).pluck("LOWER(name)")
      missing_roles = invite.roles.reject { |name| existing_names.include?(name.downcase) }
      missing_roles.each { |name| create(:role, organization: invite.organization, name: name) }
    end
  end
end
