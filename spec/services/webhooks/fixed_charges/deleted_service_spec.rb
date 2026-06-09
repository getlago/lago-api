# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::FixedCharges::DeletedService do
  subject(:webhook_service) { described_class.new(object: fixed_charge) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "fixed_charge.deleted", "fixed_charge", {
      "lago_id" => String,
      "code" => String
    }
  end
end
