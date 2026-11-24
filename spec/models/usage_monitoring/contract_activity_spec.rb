# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractActivity do
  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:contract)
    end
  end

  describe "validations" do
    it "keeps one row per contract" do
      activity = create(:contract_activity)

      expect { create(:contract_activity, organization: activity.organization, contract: activity.contract) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
