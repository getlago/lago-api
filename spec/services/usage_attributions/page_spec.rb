# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributions::Page do
  subject(:page) { described_class.new(current_page: 1, limit_value: 50, total_count:) }

  describe "#total_pages" do
    context "without groups" do
      let(:total_count) { 0 }

      it { expect(page.total_pages).to eq(0) }
    end

    context "with an exact number of pages" do
      let(:total_count) { 100 }

      it { expect(page.total_pages).to eq(2) }
    end

    context "with a partial last page" do
      let(:total_count) { 101 }

      it { expect(page.total_pages).to eq(3) }
    end
  end

  describe ".from_query_result" do
    subject(:page) { described_class.from_query_result(result) }

    let(:result) do
      UsageAttributions::QueryService::Result.new.tap do |result|
        result.limit = 50
        result.offset = 100
        result.groups_count = 120
      end
    end

    it "converts the offset to a page" do
      expect(page).to have_attributes(current_page: 3, limit_value: 50, total_count: 120, total_pages: 3)
    end
  end
end
