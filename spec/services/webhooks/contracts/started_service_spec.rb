# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Contracts::StartedService do
  subject(:webhook_service) { described_class.new(object: contract) }

  let(:contract) { create(:contract) }

  before { allow(contract.organization).to receive(:product_catalog_enabled?).and_return(true) }

  describe ".call" do
    it_behaves_like "creates webhook", "contract.started", "contract", {
      "lago_id" => String,
      "external_id" => String,
      "applied_rate_cards" => Array
    }
  end
end
