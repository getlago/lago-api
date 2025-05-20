# frozen_string_literal: true

FactoryBot.define do
  factory :commitment_applied_tax, class: "Commitment::AppliedTax" do
    commitment
    organization { commitment.organization }
    tax { association(:tax, organization:) }
  end
end
