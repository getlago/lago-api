# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::PlanRateCards::UpdatedService do
  subject(:webhook_service) { described_class.new(object: plan_rate_card) }

  let(:plan_rate_card) { create(:plan_rate_card) }

  before { allow(plan_rate_card.organization).to receive(:product_catalog_enabled?).and_return(true) }

  describe ".call" do
    it_behaves_like "creates webhook", "plan_rate_card.updated", "plan_rate_card", {
      "lago_id" => String,
      "plan_code" => String,
      "rate_card_code" => String
    }
  end
end
