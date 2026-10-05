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
end
