# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Charges::DeletedService do
  subject(:webhook_service) { described_class.new(object: charge) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "charge.deleted", "charge", {
      "lago_id" => String,
      "code" => String
    }
  end
end
