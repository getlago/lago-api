# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaignsQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, pagination:, search_term:, filters:, order:)
  end

  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { nil }
  let(:order) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:dunning_campaign_first) do
    create(:dunning_campaign, organization:, name: "defgh", code: "11", applied_to_organization: true)
  end
  let(:dunning_campaign_second) do
    create(:dunning_campaign, organization:, name: "abcde", code: "22", applied_to_organization: false)
  end

  let(:dunning_campaign_third) do
    create(
      :dunning_campaign,
      organization:,
      name: "presuv",
      code: "33",
      applied_to_organization: false
    )
  end

  before do
    dunning_campaign_first
    dunning_campaign_second
    dunning_campaign_third
  end

  it "returns all dunning campaigns ordered by name asc" do
    expect(result.dunning_campaigns).to eq(
      [dunning_campaign_second, dunning_campaign_first, dunning_campaign_third]
    )
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 2} }

    it "applies the pagination", :aggregate_failures do
      expect(result).to be_success
      expect(result.dunning_campaigns.count).to eq(1)
      expect(result.dunning_campaigns.current_page).to eq(2)
      expect(result.dunning_campaigns.prev_page).to eq(1)
      expect(result.dunning_campaigns.next_page).to be_nil
      expect(result.dunning_campaigns.total_pages).to eq(2)
      expect(result.dunning_campaigns.total_count).to eq(3)
    end
  end

  context "when searching for /de/ term" do
    let(:search_term) { "de" }

    it "returns only two dunning campaigns" do
      expect(result.dunning_campaigns).to eq([dunning_campaign_second, dunning_campaign_first])
    end
  end

  context "with applied_to_organization is false" do
    let(:filters) { {applied_to_organization: false} }

    it "returns second and third campaigns" do
      expect(result.dunning_campaigns).to eq([dunning_campaign_second, dunning_campaign_third])
    end
  end

  context "with applied_to_organization is true" do
    let(:filters) { {applied_to_organization: true} }

    it "returns only the first dunning campaign" do
      expect(result.dunning_campaigns).to eq([dunning_campaign_first])
    end
  end

  context "with currency filter" do
    let(:filters) { {currency: "USD"} }

    before do
      create(
        :dunning_campaign_threshold,
        dunning_campaign: dunning_campaign_first,
        currency: "USD"
      )

      create(
        :dunning_campaign_threshold,
        dunning_campaign: dunning_campaign_first,
        currency: "GBP"
      )

      create(
        :dunning_campaign_threshold,
        dunning_campaign: dunning_campaign_third,
        currency: "EUR"
      )
    end

    it "returns only dunning campaigns with a threshold matching the currency" do
      expect(result.dunning_campaigns).to eq([dunning_campaign_first])
    end

    context "with multiple currencies" do
      let(:filters) { {currency: ["USD", "EUR"]} }

      let(:dunning_campaign_fourth) { create(:dunning_campaign, organization:) }

      before do
        create(
          :dunning_campaign_threshold,
          dunning_campaign: dunning_campaign_fourth,
          currency: "EUR"
        )

        create(
          :dunning_campaign_threshold,
          dunning_campaign: dunning_campaign_fourth,
          currency: "USD"
        )
      end

      it "returns only dunning campaigns with a threshold matching the currency" do
        expect(result.dunning_campaigns).to eq(
          [
            dunning_campaign_fourth,
            dunning_campaign_first,
            dunning_campaign_third
          ]
        )
      end
    end
  end

  context "with order on code" do
    let(:order) { "code" }

    it "returns the dunning campaigns ordered by code" do
      expect(result.dunning_campaigns).to eq(
        [dunning_campaign_first, dunning_campaign_second, dunning_campaign_third]
      )
    end
  end
end
