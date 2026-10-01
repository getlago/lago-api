# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardSerializer do
  subject(:payload) { described_class.new(rate_card, root_name: "rate_card", includes:).serialize }

  let(:rate_card) { create(:rate_card) }
  let(:includes) { %i[active_rate rates deleted_at] }

  before { create(:rate_card_rate, organization: rate_card.organization, rate_card:, effective_from: 1.day.ago.beginning_of_day) }

  it "renders deleted_at on the card and on the rates it embeds" do
    expect(payload).to include(deleted_at: nil)
    expect(payload[:active_rate]).to include(deleted_at: nil)
    expect(payload[:rates].sole).to include(deleted_at: nil)
  end

  # As outside REST, where no caller passes deleted_at.
  context "without deleted_at" do
    let(:includes) { %i[active_rate rates counts] }

    it "renders deleted_at nowhere" do
      expect(payload).not_to have_key(:deleted_at)
      expect(payload[:active_rate]).not_to have_key(:deleted_at)
      expect(payload[:rates].sole).not_to have_key(:deleted_at)
    end
  end
end
