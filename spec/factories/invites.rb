# frozen_string_literal: true

FactoryBot.define do
  factory :invite do
    organization

    status { "pending" }
    email { Faker::Internet.email }
    token { SecureRandom.hex(20) }
    roles { %w[admin] }

    after(:build) do |invite|
      existing_codes = Role.with_code(*invite.roles).with_organization(invite.organization.id).pluck(:code)
      missed_codes = invite.roles - existing_codes
      missed_codes.each { |code| create(:role, code.to_sym) }
    end
  end
end
