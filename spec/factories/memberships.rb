# frozen_string_literal: true

FactoryBot.define do
  factory :membership do
    user
    organization
    role { 'admin' }
  end
end
