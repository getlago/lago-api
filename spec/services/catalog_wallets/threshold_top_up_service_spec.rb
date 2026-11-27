# frozen_string_literal: true

require "rails_helper"

describe CatalogWallets::ThresholdTopUpService do
  subject(:result) { described_class.call(wallet:) }

  let(:wallet) { build_stubbed(:catalog_wallet) }

  it "succeeds" do
    expect(result).to be_success
  end
end
