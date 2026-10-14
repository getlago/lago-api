# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::ContractRateCards::UpdatedService do
  subject(:webhook_service) { described_class.new(object: contract_rate_card) }

  let(:contract_rate_card) { create(:contract_rate_card) }

  before { allow(contract_rate_card.organization).to receive(:product_catalog_enabled?).and_return(true) }

  describe ".call" do
    it_behaves_like "creates webhook", "contract_rate_card.updated", "contract_rate_card", {
      "lago_id" => String,
      "external_contract_id" => String,
      "rate_card_code" => String
    }
  end
end
