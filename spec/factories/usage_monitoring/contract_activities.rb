# frozen_string_literal: true

FactoryBot.define do
  factory :contract_activity, class: "UsageMonitoring::ContractActivity" do
    association :organization
    contract { association(:contract, customer: association(:customer, organization:)) }
  end
end
