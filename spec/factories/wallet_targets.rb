# frozen_string_literal: true

FactoryBot.define do
  factory :wallet_billable_metric, class: "WalletTarget" do
    wallet
    billable_metric
    organization
  end
end
